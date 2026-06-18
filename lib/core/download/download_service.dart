import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../common/app_logger.dart';
import '../jm/jm_client.dart';
import '../jm/jm_entity.dart';
import '../jm/jm_image.dart';
import '../../data/database/task_dao.dart';
import '../../data/models/download_task_model.dart';
import '../../utils/library_storage.dart';
import '../../utils/path_helper.dart';

part 'download_progress_event.dart';
part 'download_status_emitter.dart';
part 'download_album_handler.dart';
part 'download_photo_handler.dart';

/// 下载服务 - 管理并发下载任务
///
/// 由多个 extension 分层实现：
///   - [_DownloadStatusEmitter]：进度/状态事件发射
///   - [_AlbumDownloadHandler]：整本漫画下载
///   - [_PhotoDownloadHandler]：单章漫画下载
class DownloadService
{
    /// 日志记录器（带文件输出，方便 Windows release 模式下排查问题）
    static final AppLogger _logger = AppLogger();

    final JmClient _client;
    final TaskDao _taskDao;
    final String _downloadDir;

    /// 活跃的下载任务取消器
    final Map<String, CancelToken> _cancelTokens = {};

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
          _downloadDir = downloadDir;

    /// 创建下载任务
    Future<DownloadTaskModel> createTask(
        String type,
        String jmId, {
        String? title,
        String? albumId,
        String? albumTitle,
        String? episodeIndex,
        String? episodeName,
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
            ..title = title;

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

    /// 读取已下载的加密图片，解密后覆盖保存
    Future<void> _decodeAndSave(
        String savePath,
        int scrambleId,
        int aid,
        String filename,
    ) async
    {
        try
        {
            final okPath = '$savePath.ok';
            try
            {
                if (File(okPath).existsSync())
                {
                    await File(okPath).delete();
                }
            }
            catch (_)
            {
            }

            final bytes = await File(savePath).readAsBytes();
            _logger.d('[解密] 开始: $filename, bytes=${bytes.length}');
            final decoded = await JmImage.decode(
                Uint8List.fromList(bytes),
                scrambleId,
                aid,
                filename,
            );
            await File(savePath).writeAsBytes(decoded);
            await File(okPath).writeAsString('');
            _logger.d('[解密] 成功: $filename, before=${bytes.length}, after=${decoded.length}');
        }
        catch (e, st)
        {
            _logger.w('[解密] 失败: $filename, 错误: $e');
            developer.log(
                'JmImage decode failed for $filename',
                name: 'DownloadService',
                error: e,
                stackTrace: st,
            );
        }
    }
}
