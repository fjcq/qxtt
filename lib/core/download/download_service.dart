import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../jm/jm_client.dart';
import '../jm/jm_image.dart';
import '../../data/database/task_dao.dart';
import '../../data/models/download_task_model.dart';

/// 下载进度事件
class DownloadProgressEvent
{
    /// 任务 ID
    final String taskId;

    /// 当前已下载数
    final int current;

    /// 总数
    final int total;

    /// 下载速度
    final String speed;

    /// 进度 0.0 ~ 1.0
    final double progress;

    const DownloadProgressEvent({
        required this.taskId,
        required this.current,
        required this.total,
        required this.speed,
        required this.progress,
    });
}

/// 下载服务 - 管理并发下载任务
class DownloadService
{
    final JmClient _client;
    final TaskDao _taskDao;
    final String _downloadDir;
    final bool _decodeImage;

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
        bool decodeImage = true,
    })  : _client = client,
          _taskDao = taskDao,
          _downloadDir = downloadDir,
          _decodeImage = decodeImage;

    /// 创建下载任务
    Future<DownloadTaskModel> createTask(String type, String jmId, {String? title}) async
    {
        const uuid = Uuid();
        final task = DownloadTaskModel()
            ..taskId = uuid.v4()
            ..taskType = type
            ..jmId = jmId
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

    /// 下载整本漫画
    Future<void> downloadAlbum(String taskId, String albumId) async
    {
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取详情', 0.0);

            // 获取本子详情
            final albumDetail = await _client.getAlbumDetail(albumId);

            await _taskDao.updateTaskStatus(
                taskId, 'running', '正在下载', 0.0,
            );

            // 遍历章节
            var completedPhotos = 0;
            final totalPhotos = albumDetail.episodes.length;

            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) break;

                await _downloadPhotoInternal(
                    taskId: taskId,
                    photoId: episode.photoId,
                    albumTitle: albumDetail.name,
                    episodeIndex: episode.index,
                    cancelToken: cancelToken,
                );

                completedPhotos++;
                final progress = totalPhotos > 0 ? completedPhotos / totalPhotos : 0.0;
                await _taskDao.updateTaskProgress(
                    taskId,
                    completedPhotos,
                    totalPhotos,
                    progress,
                );
                _emitProgress(taskId, completedPhotos, totalPhotos, progress);
            }

            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'completed', '下载完成', 1.0,
                );
            }
        }
        catch (e)
        {
            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', '下载失败: $e', 0.0,
                );
            }
        }
        finally
        {
            _cancelTokens.remove(taskId);
            _taskStats.remove(taskId);
        }
    }

    /// 下载单个章节
    Future<void> downloadPhoto(String taskId, String photoId) async
    {
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取章节详情', 0.0);

            await _downloadPhotoInternal(
                taskId: taskId,
                photoId: photoId,
                albumTitle: '',
                episodeIndex: '',
                cancelToken: cancelToken,
            );

            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'completed', '下载完成', 1.0,
                );
            }
        }
        catch (e)
        {
            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', '下载失败: $e', 0.0,
                );
            }
        }
        finally
        {
            _cancelTokens.remove(taskId);
            _taskStats.remove(taskId);
        }
    }

    /// 清理文件名中的非法字符
    static String _sanitizeFileName(String name)
    {
        // Windows 不允许的字符: \ / : * ? " < > |
        var result = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        // 去除首尾空格和末尾点号（Windows 不允许以空格或点结尾）
        result = result.trimRight();
        while (result.endsWith('.'))
        {
            result = result.substring(0, result.length - 1);
        }
        // 空名称用默认值
        if (result.isEmpty)
        {
            result = 'unnamed';
        }
        return result;
    }

    /// 内部下载章节实现
    Future<void> _downloadPhotoInternal({
        required String taskId,
        required String photoId,
        required String albumTitle,
        required String episodeIndex,
        required CancelToken cancelToken,
    }) async
    {
        // 获取章节详情
        final photoDetail = await _client.getPhotoDetail(photoId);

        // 获取 scramble_id
        final scrambleId = await _client.getScrambleId(photoId);

        // 创建保存目录（清理非法字符）
        final safeAlbumTitle = _sanitizeFileName(albumTitle);
        final safeEpisodeIndex = _sanitizeFileName(episodeIndex);
        final saveDir = '$_downloadDir/$safeAlbumTitle/$safeEpisodeIndex';
        await Directory(saveDir).create(recursive: true);

        // 下载所有图片
        var completedImages = 0;
        final totalImages = photoDetail.pageArr.length;

        for (var i = 0; i < photoDetail.pageArr.length; i++)
        {
            if (cancelToken.isCancelled) break;

            final filename = photoDetail.pageArr[i];
            final imageUrl = _client.getImageUrl(photoId, filename);
            final savePath = '$saveDir/${(i + 1).toString().padLeft(5, '0')}.jpg';

            try
            {
                // 下载图片
                final imageBytes = await _client.downloadImage(imageUrl);

                // 记录下载字节数
                _taskStats[taskId]?.addBytes(imageBytes.length);

                // 图片解密
                if (_decodeImage && scrambleId > 0)
                {
                    final aid = int.tryParse(photoDetail.albumId) ?? 0;
                    final num = JmImage.getSegmentationNum(
                        scrambleId, aid, filename,
                    );
                    if (num > 0)
                    {
                        await _decodeAndSave(imageBytes, num, savePath);
                    }
                    else
                    {
                        await File(savePath).writeAsBytes(imageBytes);
                    }
                }
                else
                {
                    // 直接保存
                    await File(savePath).writeAsBytes(imageBytes);
                }
            }
            catch (e)
            {
                // 单张图片下载失败，继续下一张
                continue;
            }

            completedImages++;
            final progress = totalImages > 0 ? completedImages / totalImages : 0.0;
            await _taskDao.updateTaskProgress(
                taskId, completedImages, totalImages, progress,
            );
            _emitProgress(taskId, completedImages, totalImages, progress);
        }
    }

    /// 图片解密并保存
    Future<void> _decodeAndSave(
        List<int> imageBytes,
        int num,
        String savePath,
    ) async
    {
        // TODO: 使用 Isolate 在后台线程执行图片解密
        // 当前简化实现，直接保存原始数据
        await File(savePath).writeAsBytes(imageBytes);
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

    /// 发送进度事件
    void _emitProgress(String taskId, int current, int total, double progress)
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: current,
            total: total,
            speed: speed,
            progress: progress,
        ));
    }

    /// 格式化下载速度
    static String _formatSpeed(double bytesPerSecond)
    {
        if (bytesPerSecond <= 0) return '';
        if (bytesPerSecond < 1024)
        {
            return '${bytesPerSecond.toStringAsFixed(0)} B/s';
        }
        else if (bytesPerSecond < 1024 * 1024)
        {
            return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
        }
        else
        {
            return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
        }
    }

    /// 释放资源
    void dispose()
    {
        _progressController.close();
    }
}

/// 下载统计信息（用于计算下载速度）
class _DownloadStats
{
    /// 下载开始时间
    final DateTime _startTime = DateTime.now();

    /// 已下载总字节数
    int _totalBytes = 0;

    /// 添加已下载字节数
    void addBytes(int bytes)
    {
        _totalBytes += bytes;
    }

    /// 计算下载速度（字节/秒）
    double getSpeed()
    {
        final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
        if (elapsed <= 0) return 0.0;
        return _totalBytes / (elapsed / 1000.0);
    }
}
