part of 'download_service.dart';

/// 负责单章（photo）下载
extension DownloadServicePhotoHandler on DownloadService
{
    /// 下载单个章节
    ///
    /// 单章内所有图片通过 [DownloadSemaphore] 并发下载，并发数取
    /// [_imageThreadCount]。每条下载任务会从 [DomainRotator] 取一个
    /// 起始域名下标，使不同线程优先使用不同图片域名。
    ///
    /// 断点续传：若任务是从 `paused` 状态恢复的，会先扫描本地已有图片数，
    /// 跳过已下载的页。
    Future<void> downloadPhoto(DownloadTaskModel task) async
    {
        final taskId = task.taskId;
        final photoId = task.jmId;
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();
        var wasPaused = false;

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取章节详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取章节详情', 0.0);

            final photoDetail = await _client.getPhotoDetail(photoId);
            final scrambleId = await _client.getScrambleId(photoId);

            if (cancelToken.isCancelled) return;

            final totalImages = photoDetail.pageArr.length;

            final downloadDir = _downloadDir.isEmpty
                ? await PathHelper.getDownloadDir()
                : _downloadDir;
            final String saveDir;
            if (task.albumTitle.isNotEmpty && task.episodeIndex.isNotEmpty)
            {
                final safeAlbumTitle = DownloadService._sanitizeFileName(task.albumTitle);
                final safeEpisodeIndex = DownloadService._sanitizeFileName(task.episodeIndex);
                saveDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle${Platform.pathSeparator}$safeEpisodeIndex';
            }
            else
            {
                saveDir = '$downloadDir${Platform.pathSeparator}$photoId';
            }
            await Directory(saveDir).create(recursive: true);

            // 断点续传：扫描本地已有图片
            final completed = <int>{};
            for (var i = 0; i < photoDetail.pageArr.length; i++)
            {
                if (_isImageDownloaded(saveDir, i)) completed.add(i);
            }

            // 写入初始进度
            await _taskDao.updateTaskProgress(
                taskId, completed.length, totalImages,
                totalImages > 0 ? completed.length / totalImages : 0.0,
            );
            _emitProgress(
                taskId, completed.length, totalImages,
                totalImages > 0 ? completed.length / totalImages : 0.0,
                'running', completed.isNotEmpty ? '续传中' : '正在下载',
            );

            // 暂停监听
            void onPauseSignal()
            {
                if (_pausedTasks.contains(taskId))
                {
                    wasPaused = true;
                    if (!cancelToken.isCancelled)
                    {
                        cancelToken.cancel('用户暂停下载');
                    }
                }
            }

            await _runConcurrentImageDownload(
                taskId: taskId,
                photoId: photoId,
                pageArr: photoDetail.pageArr,
                scrambleId: scrambleId,
                saveDir: saveDir,
                cancelToken: cancelToken,
                runningMessage: '正在下载',
                preCompleted: completed,
                onPauseCheck: onPauseSignal,
            );

            // 处理暂停
            if (wasPaused || cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'paused', '已暂停', 0.0,
                );
                _emitStatus(taskId, 'paused', '已暂停', 0.0);
                return;
            }

            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'completed', '下载完成', 1.0,
                );
                final firstImage = '$saveDir${Platform.pathSeparator}00001.jpg';
                final coverPath = await _ensurePhotoCover(saveDir, firstImage);
                if (task.albumTitle.isNotEmpty && task.episodeIndex.isNotEmpty)
                {
                    final albumDir = Directory(saveDir).parent.path;
                    await LibraryStorage.updateAlbumMetadataWithEpisode(
                        albumDir,
                        photoId: photoId,
                        index: task.episodeIndex,
                        name: task.episodeName,
                        albumId: task.albumId,
                        title: task.albumTitle,
                    );
                }
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0, [photoId],
                    localCoverPath: coverPath,
                    localPath: saveDir,
                );
            }
        }
        catch (e)
        {
            if (wasPaused || _pausedTasks.contains(taskId))
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'paused', '已暂停', 0.0,
                );
                _emitStatus(taskId, 'paused', '已暂停', 0.0);
            }
            else if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', '下载失败: $e', 0.0,
                );
                _emitStatus(taskId, 'failed', '下载失败: $e', 0.0);
            }
        }
        finally
        {
            _cancelTokens.remove(taskId);
            _taskStats.remove(taskId);
        }
    }

    /// 并发下载一个章节下的所有图片（共享给 photo / album 流程）
    ///
    /// 使用 [DownloadSemaphore] 限制同时下载数（= [_imageThreadCount]），
    /// 通过 [DomainRotator] 让每条线程从不同域名开始尝试。
    /// 进度基于 [Set] 收集已完成的 pageIndex，避免乱序上报错位。
    ///
    /// [preCompleted] 为续传时已存在的页索引集合，会被预填到 [completed]。
    /// [onPauseCheck] 在每张图下载前调用，用于检查是否需要触发 cancel。
    Future<void> _runConcurrentImageDownload({
        required String taskId,
        required String photoId,
        required List<String> pageArr,
        required int scrambleId,
        required String saveDir,
        required CancelToken cancelToken,
        required String runningMessage,
        Set<int> preCompleted = const <int>{},
        void Function()? onPauseCheck,
    }) async
    {
        final totalImages = pageArr.length;
        final aid = int.tryParse(photoId) ?? 0;
        final semaphore = DownloadSemaphore(_imageThreadCount);
        final rotator = DomainRotator(_client.imageDomainList.length);
        final completed = <int>{...preCompleted};
        final futures = <Future<void>>[];

        Future<void> reportProgress()
        {
            final doneCount = completed.length;
            final progress = totalImages > 0 ? doneCount / totalImages : 0.0;
            // 进度上报不阻塞后续任务
            return _taskDao.updateTaskProgress(
                taskId, doneCount, totalImages, progress,
            ).then((_) => _emitProgress(
                taskId, doneCount, totalImages, progress,
                'running', runningMessage,
            ));
        }

        Future<void> downloadOne(int pageIndex, String filename) async
        {
            // 续传：本地已有则直接跳过
            if (completed.contains(pageIndex)) return;
            onPauseCheck?.call();
            if (cancelToken.isCancelled) return;
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
                if (result.success && result.bytes > 0)
                {
                    _taskStats[taskId]?.addBytes(result.bytes);
                }
                completed.add(pageIndex);
                await reportProgress();
            }
            finally
            {
                semaphore.release();
            }
        }

        for (var i = 0; i < pageArr.length; i++)
        {
            if (cancelToken.isCancelled) break;
            // 续传：本地已有则跳过
            if (completed.contains(i)) continue;
            futures.add(downloadOne(i, pageArr[i]));
        }

        // 等待所有任务结束；被取消时让已开始的自然结束即可
        await Future.wait(futures);
    }

    /// 单图是否已存在且有效
    bool _isImageDownloaded(String saveDir, int pageIndex)
    {
        final savePath = '$saveDir${Platform.pathSeparator}${(pageIndex + 1).toString().padLeft(5, '0')}.jpg';
        final okPath = '$savePath.ok';
        return File(savePath).existsSync() && File(okPath).existsSync();
    }

    /// 确保 photo 任务有 cover.jpg
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
}
