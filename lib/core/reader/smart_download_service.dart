import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/task_dao.dart';
import '../../data/models/download_task_model.dart';
import '../../utils/library_storage.dart';
import '../../utils/path_helper.dart';
import '../common/app_logger.dart';
import '../jm/jm_client.dart';
import '../download/concurrent_image_downloader.dart';
import 'network_monitor.dart';

/// 智能下载进度事件
class SmartDownloadProgress
{
    /// 任务 ID
    final String taskId;

    /// 当前完成图片数
    final int currentImage;

    /// 总图片数
    final int totalImages;

    /// 0.0 ~ 1.0
    final double progress;

    /// 状态
    final String status;

    /// 提示信息
    final String message;

    const SmartDownloadProgress({
        required this.taskId,
        required this.currentImage,
        required this.totalImages,
        required this.progress,
        required this.status,
        required this.message,
    });
}

/// 智能下载服务
/// 在线阅读时自动将当前章节以与主动下载完全一致的格式保存到本地，
/// 生成 .ok 标记并写入 TaskDao，使其可在下载管理与书架中正常识别。
///
/// 并发原语（信号量、域名轮询、单图下载+解密）共用
/// [concurrent_image_downloader.dart]，与 [DownloadService] 整本下载保持一致。
class SmartDownloadService
{
    static final AppLogger _logger = AppLogger();

    final JmClient _client;
    final TaskDao _taskDao;
    final String _downloadDir;
    final NetworkMonitor _networkMonitor;

    /// 图片级并发数（默认 5）
    int _imageThreadCount;

    /// 活跃任务取消器：photoId -> CancelToken
    final Map<String, CancelToken> _cancelTokens = {};

    /// 进度流
    final _progressController = StreamController<SmartDownloadProgress>.broadcast();

    SmartDownloadService({
        required JmClient client,
        required TaskDao taskDao,
        required String downloadDir,
        NetworkMonitor? networkMonitor,
        int imageThreadCount = 5,
    })  : _client = client,
          _taskDao = taskDao,
          _downloadDir = downloadDir,
          _networkMonitor = networkMonitor ?? NetworkMonitor(),
          _imageThreadCount = imageThreadCount.clamp(1, 10);

    /// 下载进度流
    Stream<SmartDownloadProgress> get onProgress => _progressController.stream;

    /// 设置并发数
    set imageThreadCount(int value)
    {
        _imageThreadCount = value.clamp(1, 10);
    }

    /// 启动智能下载
    /// [photoId] 章节 ID
    /// [albumTitle] 本子标题（用于构建标准下载目录）
    /// [episodeIndex] 章节序号
    /// [episodeName] 章节名称
    /// [albumId] 本子 ID
    /// 若该 photoId 已存在任务（任意状态），则不重复创建
    Future<void> startSmartDownload({
        required String photoId,
        String albumTitle = '',
        String episodeIndex = '',
        String episodeName = '',
        String albumId = '',
    }) async
    {
        await _networkMonitor.init();
        if (_networkMonitor.isOffline) return;

        // 避免重复创建
        final existing = await _findExistingTask(photoId);
        if (existing != null) return;

        final cancelToken = CancelToken();
        _cancelTokens[photoId] = cancelToken;

        final task = await _createTask(
            photoId: photoId,
            albumTitle: albumTitle,
            episodeIndex: episodeIndex,
            episodeName: episodeName,
            albumId: albumId,
        );

        try
        {
            await _taskDao.updateTaskStatus(
                task.taskId, 'running', '正在获取章节详情', 0.0,
            );
            _emit(task.taskId, 0, 0, 0.0, 'running', '正在获取章节详情');

            final photoDetail = await _client.getPhotoDetail(photoId);
            final scrambleId = await _client.getScrambleId(photoId);

            if (cancelToken.isCancelled) return;

            final totalImages = photoDetail.pageArr.length;
            await _taskDao.updateTaskProgress(
                task.taskId, 0, totalImages, 0.0,
            );
            _emit(task.taskId, 0, totalImages, 0.0, 'running', '智能下载中');

            final saveDir = await _ensureSaveDir(
                photoId: photoId,
                albumTitle: albumTitle,
                episodeIndex: episodeIndex,
            );

            final aid = int.tryParse(photoId) ?? 0;
            final semaphore = DownloadSemaphore(_imageThreadCount);
            final rotator = DomainRotator(_client.imageDomainList.length);
            final completed = <int>{};
            final futures = <Future<void>>[];

            Future<void> reportProgress() async
            {
                final doneCount = completed.length;
                final progress = totalImages > 0
                    ? doneCount / totalImages
                    : 0.0;
                await _taskDao.updateTaskProgress(
                    task.taskId, doneCount, totalImages, progress,
                );
                _emit(
                    task.taskId,
                    doneCount,
                    totalImages,
                    progress,
                    'running',
                    '智能下载中',
                );
            }

            Future<void> downloadOne(int pageIndex, String filename) async
            {
                await semaphore.acquire();
                try
                {
                    if (cancelToken.isCancelled) return;
                    final result = await downloadOneImageWithDecode(
                        client: _client,
                        cancelToken: cancelToken,
                        photoId: photoId,
                        filename: filename,
                        pageIndex: pageIndex,
                        saveDir: saveDir,
                        scrambleId: scrambleId,
                        aid: aid,
                        rotator: rotator,
                    );
                    if (!result.success)
                    {
                        _logger.w('[智能下载] $photoId/$filename 失败');
                    }
                    completed.add(pageIndex);
                    await reportProgress();
                }
                finally
                {
                    semaphore.release();
                }
            }

            for (var i = 0; i < photoDetail.pageArr.length; i++)
            {
                if (cancelToken.isCancelled) break;
                futures.add(downloadOne(i, photoDetail.pageArr[i]));
            }

            await Future.wait(futures);
            if (cancelToken.isCancelled) return;

            await _taskDao.updateTaskStatus(
                task.taskId, 'completed', '下载完成', 1.0,
            );
            _emit(task.taskId, totalImages, totalImages, 1.0, 'completed', '下载完成');

            // 更新元数据
            await _updateMetadata(
                saveDir: saveDir,
                photoId: photoId,
                albumTitle: albumTitle,
                episodeIndex: episodeIndex,
                episodeName: episodeName,
                albumId: albumId,
                scrambleId: scrambleId,
                pageArr: photoDetail.pageArr,
            );
            // 【性能优化 P2】智能下载完成时写章节级 .complete，
            // 并删除该章节所有 .ok 碎片文件
            await ChapterCompleteHelper.markChapterComplete(
                saveDir, photoDetail.pageArr.length,
            );
            await ChapterCompleteHelper.removeAllOkMarks(saveDir);
        }
        catch (e)
        {
            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    task.taskId, 'failed', '下载失败: $e', 0.0,
                );
                _emit(task.taskId, 0, 0, 0.0, 'failed', '下载失败: $e');
            }
        }
        finally
        {
            _cancelTokens.remove(photoId);
        }
    }

    /// 取消指定章节的智能下载
    void cancel(String photoId)
    {
        final token = _cancelTokens[photoId];
        if (token != null && !token.isCancelled)
        {
            token.cancel('用户取消');
        }
    }

    /// 取消所有智能下载任务
    void cancelAll()
    {
        for (final token in _cancelTokens.values)
        {
            if (!token.isCancelled)
            {
                token.cancel('取消全部');
            }
        }
    }

    /// 释放资源
    void dispose()
    {
        cancelAll();
        _progressController.close();
        _networkMonitor.dispose();
    }

    /// 查找是否已存在该章节的任务
    Future<DownloadTaskModel?> _findExistingTask(String photoId) async
    {
        final tasks = await _taskDao.getAllTasks();
        return tasks.where((t) => t.jmId == photoId).firstOrNull;
    }

    /// 创建智能下载任务
    Future<DownloadTaskModel> _createTask({
        required String photoId,
        required String albumTitle,
        required String episodeIndex,
        required String episodeName,
        required String albumId,
    }) async
    {
        const uuid = Uuid();
        final task = DownloadTaskModel()
            ..taskId = uuid.v4()
            ..taskType = 'smart_download'
            ..jmId = photoId
            ..albumId = albumId
            ..albumTitle = albumTitle
            ..episodeIndex = episodeIndex
            ..episodeName = episodeName
            ..status = 'pending'
            ..message = '等待智能下载'
            ..createdAt = DateTime.now().toIso8601String()
            ..updatedAt = DateTime.now().toIso8601String()
            ..progress = 0.0
            ..currentImage = 0
            ..totalImages = 0
            ..title = episodeName.isNotEmpty ? episodeName : photoId;

        await _taskDao.createTask(task);
        return task;
    }

    /// 确保保存目录存在
    Future<String> _ensureSaveDir({
        required String photoId,
        required String albumTitle,
        required String episodeIndex,
    }) async
    {
        final downloadDir = _downloadDir.isEmpty
            ? await PathHelper.getDownloadDir()
            : _downloadDir;
        final sep = Platform.pathSeparator;

        late final String saveDir;
        if (albumTitle.isNotEmpty && episodeIndex.isNotEmpty)
        {
            final safeAlbum = _sanitizeFileName(albumTitle);
            final safeEpisode = _sanitizeFileName(episodeIndex);
            saveDir = '$downloadDir$sep$safeAlbum$sep$safeEpisode';
        }
        else
        {
            saveDir = '$downloadDir$sep$photoId';
        }

        await Directory(saveDir).create(recursive: true);
        return saveDir;
    }

    /// 更新章节元数据与封面
    Future<void> _updateMetadata({
        required String saveDir,
        required String photoId,
        required String albumTitle,
        required String episodeIndex,
        required String episodeName,
        required String albumId,
        required int scrambleId,
        required List<String> pageArr,
    }) async
    {
        try
        {
            final firstImage = '$saveDir${Platform.pathSeparator}00001.jpg';
            final coverPath = await _ensurePhotoCover(saveDir, firstImage);

            if (albumTitle.isNotEmpty && episodeIndex.isNotEmpty)
            {
                final albumDir = Directory(saveDir).parent.path;
                // 一并持久化 scrambleId + pageArr，
                // 阅读器离线打开时可跳过 getPhotoDetail / getScrambleId 网络请求
                await LibraryStorage.saveChapterMetadata(
                    albumDir,
                    photoId: photoId,
                    index: episodeIndex,
                    name: episodeName,
                    scrambleId: scrambleId,
                    pageArr: pageArr,
                    albumId: albumId,
                    title: albumTitle,
                );
            }

            // 查找任务并更新本地路径与封面
            final tasks = await _taskDao.getAllTasks();
            final task = tasks.where((t) => t.jmId == photoId).firstOrNull;
            if (task != null)
            {
                task.localPath = saveDir;
                task.coverPath = coverPath;
                task.updatedAt = DateTime.now().toIso8601String();
                await _taskDao.updateTaskStatus(
                    task.taskId, 'completed', '下载完成', 1.0,
                );
            }
        }
        catch (e)
        {
            _logger.w('[智能下载] 更新元数据失败: $e');
        }
    }

    /// 确保章节目录存在 cover.jpg
    Future<String> _ensurePhotoCover(String saveDir, String firstImage) async
    {
        final cover = '$saveDir${Platform.pathSeparator}cover.jpg';
        final coverFile = File(cover);
        if (await coverFile.exists()) return cover;
        final src = File(firstImage);
        if (!await src.exists()) return '';
        try
        {
            await src.copy(cover);
            return cover;
        }
        catch (_)
        {
            return firstImage;
        }
    }

    /// 发射进度事件
    void _emit(
        String taskId,
        int currentImage,
        int totalImages,
        double progress,
        String status,
        String message,
    )
    {
        if (_progressController.isClosed) return;
        _progressController.add(SmartDownloadProgress(
            taskId: taskId,
            currentImage: currentImage,
            totalImages: totalImages,
            progress: progress,
            status: status,
            message: message,
        ));
    }

    /// 清理文件名中的非法字符
    static String _sanitizeFileName(String name)
    {
        var result = name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
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
