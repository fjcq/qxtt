import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../jm/jm_client.dart';
import '../jm/jm_entity.dart';
import '../../data/database/task_dao.dart';
import '../../data/models/download_task_model.dart';
import '../../utils/library_storage.dart';
import '../../utils/path_helper.dart';
import '../../utils/file_helper.dart';
import 'concurrent_image_downloader.dart';

part 'download_progress_event.dart';
part 'download_status_emitter.dart';
part 'download_album_handler.dart';
part 'download_album_cover.dart';
part 'download_photo_handler.dart';

/// 下载服务 - 管理并发下载任务
///
/// 由多个 extension 分层实现：
///   - [_DownloadStatusEmitter]：进度/状态事件发射
///   - [_AlbumDownloadHandler]：整本漫画下载
///   - [_PhotoDownloadHandler]：单章漫画下载
///
/// 单个任务内部采用"章节串行 + 章节内图片并发"策略：整本按章节顺序逐章下载，
/// 单章内的所有图片一起抢 [_imageThreadCount] 个许可并发下载，前面的章节
/// 先完成以便用户边下边读，与 [SmartDownloadService] 共享
/// [concurrent_image_downloader] 中的并发原语。
///
/// 暂停/继续：
///   - [pauseTask] 取消正在进行的 HTTP 请求，保留已下载的部分文件，
///     并把任务状态置为 `paused`。
///   - [resumeTask] 重新派发任务；下载流程在派发时会先扫描本地已有图片并跳过，
///     实现"图片级断点续传"。
class DownloadService
{
    final JmClient _client;
    final TaskDao _taskDao;
    final String _downloadDir;

    /// 图片级并发数：同时下载的图片数（整本内不区分章节）。
    /// 可被 [imageThreadCount] setter 动态调整，与阅读侧共用同一上限 1~10。
    int _imageThreadCount;

    /// 活跃的下载任务取消器
    final Map<String, CancelToken> _cancelTokens = {};

    /// 处于暂停状态的任务 ID（pause 后被 cancel 移除但状态置为 paused，
    /// resume 时据此判断是续传而非新增）
    final Set<String> _pausedTasks = {};

    /// 下载进度流控制器
    final _progressController = StreamController<DownloadProgressEvent>.broadcast();

    /// 下载进度流
    Stream<DownloadProgressEvent> get onProgress => _progressController.stream;

    /// 每个任务的下载统计信息
    final Map<String, _DownloadStats> _taskStats = {};

    DownloadService({
        required JmClient client,
        required TaskDao taskDao,
        required String downloadDir,
        int imageThreadCount = 5,
        int photoThreadCount = 3,
    })  : _client = client,
          _taskDao = taskDao,
          _downloadDir = downloadDir,
          _imageThreadCount = imageThreadCount.clamp(1, 10);

    /// 当前生效的图片并发数
    int get imageThreadCount => _imageThreadCount;

    /// 动态调整图片并发数（仅影响此后新建的下载批次内的并发上限；
    /// 已经在跑的批次信号量不变，避免中断进行中的下载）
    set imageThreadCount(int value)
    {
        _imageThreadCount = value.clamp(1, 10);
    }

    /// 创建下载任务
    ///
    /// [source] 任务来源：
    ///   - `manual`（默认）：用户主动下载
    ///   - `reading`：阅读产生的下载任务
    Future<DownloadTaskModel> createTask(
        String type,
        String jmId, {
        String? title,
        String? albumId,
        String? albumTitle,
        String? episodeIndex,
        String? episodeName,
        String source = 'manual',
    }) async
    {
        const uuid = Uuid();
        final task = DownloadTaskModel()
            ..taskId = uuid.v4()
            ..taskType = type
            ..jmId = jmId
            ..albumId = albumId ?? (type == 'album' ? jmId : '')
            ..albumTitle = albumTitle ?? ''
            ..episodeIndex = episodeIndex ?? ''
            ..episodeName = episodeName ?? ''
            ..status = 'pending'
            ..message = '等待下载'
            ..createdAt = DateTime.now().toIso8601String()
            ..updatedAt = DateTime.now().toIso8601String()
            ..progress = 0.0
            ..currentImage = 0
            ..totalImages = 0
            ..title = title
            ..source = source;

        await _taskDao.createTask(task);
        return task;
    }

    /// 取消下载任务
    void cancelTask(String taskId)
    {
        final cancelToken = _cancelTokens[taskId];
        if (cancelToken != null && !cancelToken.isCancelled)
        {
            cancelToken.cancel('用户取消下载');
        }
    }

    /// 暂停下载任务
    /// - 取消正在进行的 HTTP 请求
    /// - 状态置为 `paused`，保留本地已下载的部分文件
    /// - 不会触发自动归档
    void pauseTask(String taskId)
    {
        // 标记为暂停任务；resume 时据此重派
        _pausedTasks.add(taskId);
        // 取消 in-flight 请求
        final cancelToken = _cancelTokens[taskId];
        if (cancelToken != null && !cancelToken.isCancelled)
        {
            cancelToken.cancel('用户暂停下载');
        }
    }

    /// 清除任务的暂停标记
    ///
    /// 必须在重新派发下载（resume / retry / 启动恢复）之前调用，
    /// 否则 [onPauseSignal] 会把本次下载误判为"需要暂停"并立即取消。
    void clearPausedFlag(String taskId)
    {
        _pausedTasks.remove(taskId);
    }

    /// 是否处于暂停态
    bool isPaused(String taskId) => _pausedTasks.contains(taskId);

    /// 释放资源
    void dispose()
    {
        _progressController.close();
    }

    /// 清理文件名中的非法字符
    static String _sanitizeFileName(String name)
    {
        var result = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        result = result.trimRight();
        while (result.endsWith('.'))
        {
            result = result.substring(0, result.length - 1);
        }
        if (result.isEmpty)
        {
            result = 'unnamed';
        }
        return result;
    }
}
