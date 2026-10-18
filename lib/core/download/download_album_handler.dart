part of 'download_service.dart';

/// 负责整本（album）下载
extension DownloadServiceAlbumHandler on DownloadService
{
    /// 下载整本漫画
    ///
    /// 流程：
    /// 1. 拉取本子详情与所有章节的 photoDetail
    /// 2. **全任务并发**：所有章节的所有图片一起抢 [_imageThreadCount] 个许可，
    ///    章节之间不再串行。取消时停止派发新任务，已开始的会自然结束。
    /// 3. 全部完成后回写本子元数据与封面。
    ///
    /// 断点续传：若任务是从 `paused` 状态恢复的，会先扫描本地已有图片数，
    /// 将其纳入初始计数，避免重复下载。
    Future<void> downloadAlbum(String taskId, String albumId) async
    {
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        final downloadedPhotoIds = <String>{};
        // 边下边看集合：任意一张图下载完成即把对应章节加入，用于 UI 立即显示「阅读」入口
        final partialDownloadedPhotoIds = <String>{};
        // 本次运行是否因为暂停而中止
        var wasPaused = false;

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取详情', 0.0);

            final albumDetail = await _client.getAlbumDetail(albumId);

            if (cancelToken.isCancelled) return;

            // 先并行获取所有章节的详情 + scrambleId，加速启动
            final detailByPhotoId = <String, PhotoDetail>{};
            final scrambleIds = <String, int>{};
            final detailFutures = <Future<void>>[];
            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) break;
                final photoId = episode.photoId;
                detailFutures.add(() async
                {
                    final detail = await _client.getPhotoDetail(photoId);
                    // 优先使用 APP API 响应自带的 scramble_id，仅缺失时走 HTML 兜底
                    final scrambleId = detail.scrambleId != 0
                        ? detail.scrambleId
                        : await _client.getScrambleId(photoId);
                    if (cancelToken.isCancelled) return;
                    detailByPhotoId[photoId] = detail;
                    scrambleIds[photoId] = scrambleId;
                }());
            }
            await Future.wait(detailFutures);
            if (cancelToken.isCancelled) return;

            var totalImages = 0;
            for (final detail in detailByPhotoId.values)
            {
                totalImages += detail.pageArr.length;
            }

            if (albumDetail.episodes.isNotEmpty)
            {
                await _taskDao.updateFirstPhotoId(
                    taskId, albumDetail.episodes.first.photoId,
                );
            }

            final safeAlbumTitle = DownloadService._sanitizeFileName(albumDetail.name);
            final downloadDir = _downloadDir.isEmpty
                ? await PathHelper.getDownloadDir()
                : _downloadDir;

            // 断点续传：扫描本地已有图片，纳入初始完成集合
            // 这样进度条与持久化的 currentImage 不会因为续传而从 0 跳到 N
            final completedImages = <_AlbumImageKey>{};
            // 断点续传：扫描本地已有图片
            final albumDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle';
            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) break;
                final detail = detailByPhotoId[episode.photoId];
                if (detail == null) continue;
                final safeEpisodeIndex =
                    DownloadService._sanitizeFileName(episode.index);
                final saveDir = '$albumDir${Platform.pathSeparator}$safeEpisodeIndex';
                for (var i = 0; i < detail.pageArr.length; i++)
                {
                    if (await _isImageDownloaded(saveDir, i))
                    {
                        completedImages.add(_AlbumImageKey(episode.photoId, i));
                    }
                }
            }
            // 恢复时把"已有至少一张图"的章节也加入边下边看集合
            partialDownloadedPhotoIds.addAll(
                completedImages.map((k) => k.photoId),
            );

            // 写入初始进度（如果存在已下载图片则不从 0 开始）
            await _taskDao.updateTaskProgress(
                taskId, completedImages.length, totalImages,
                totalImages > 0 ? completedImages.length / totalImages : 0.0,
            );
            _emitProgress(
                taskId, completedImages.length, totalImages,
                totalImages > 0 ? completedImages.length / totalImages : 0.0,
                'running', completedImages.isNotEmpty ? '续传中' : '正在下载',
            );
            // 续传时若有已部分下载的章节，立即推送一次边下边看事件，让 UI 显示「阅读」按钮
            if (partialDownloadedPhotoIds.isNotEmpty)
            {
                _emitPartialProgress(
                    taskId,
                    albumDetail,
                    downloadedPhotoIds,
                    partialDownloadedPhotoIds,
                    totalImages,
                );
            }

            // 全任务并发：所有章节共用一个信号量
            final semaphore = DownloadSemaphore(_imageThreadCount);
            final rotator = DomainRotator(_client.imageDomainList.length);
            final futures = <Future<String>>[]; // 返回 saveDir，用于最后兜底封面
            String lastSaveDir = '';

            Future<void> reportProgress()
            {
                final doneCount = completedImages.length;
                final progress = totalImages > 0 ? doneCount / totalImages : 0.0;
                return _taskDao.updateTaskProgress(
                    taskId, doneCount, totalImages, progress,
                ).then((_) => _emitProgress(
                    taskId, doneCount, totalImages, progress,
                    'running', '正在下载',
                ));
            }

            /// 监听暂停：若被标记为暂停，将 cancelToken 触发并设置 wasPaused
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

            Future<String> downloadEpisode(Episode episode, PhotoDetail detail) async
            {
                if (cancelToken.isCancelled) return '';
                final scrambleId = scrambleIds[episode.photoId] ?? 0;
                final safeEpisodeIndex = DownloadService._sanitizeFileName(episode.index);
                final saveDir = '$albumDir${Platform.pathSeparator}$safeEpisodeIndex';
                await Directory(saveDir).create(recursive: true);
                final aid = int.tryParse(episode.photoId) ?? 0;

                for (var i = 0; i < detail.pageArr.length; i++)
                {
                    if (cancelToken.isCancelled) break;
                    // 续传：本地已有且 .ok 标记则跳过
                    if (completedImages.contains(_AlbumImageKey(episode.photoId, i)))
                    {
                        continue;
                    }
                    final filename = detail.pageArr[i];
                    onPauseSignal();
                    if (cancelToken.isCancelled) break;
                    await semaphore.acquire();
                    try
                    {
                        if (cancelToken.isCancelled) continue;
                        final result = await downloadOneImageWithDecode(
                            client: _client,
                            cancelToken: cancelToken,
                            photoId: episode.photoId,
                            filename: filename,
                            pageIndex: i,
                            saveDir: saveDir,
                            scrambleId: scrambleId,
                            aid: aid,
                            rotator: rotator,
                        );
                        if (result.success && result.bytes > 0)
                        {
                            _taskStats[taskId]?.addBytes(result.bytes);
                        }
                        completedImages.add(_AlbumImageKey(episode.photoId, i));
                        // 边下边看：只要有一张图下载成功，立即把该章节加入部分可读集合
                        if (partialDownloadedPhotoIds.add(episode.photoId))
                        {
                            _emitPartialProgress(
                                taskId,
                                albumDetail,
                                downloadedPhotoIds,
                                partialDownloadedPhotoIds,
                                totalImages,
                            );
                        }
                        // 增量：单章全部下载完成后立即把该章节写入 library
                        if (_isEpisodeComplete(detail.pageArr.length, episode.photoId, completedImages))
                        {
                            downloadedPhotoIds.add(episode.photoId);
                            // 【性能优化 P2】整章完成时写章节级 .complete 标记，
                            // 并删除该章节所有 .ok 碎片文件
                            await ChapterCompleteHelper.markChapterComplete(
                                saveDir, detail.pageArr.length,
                            );
                            await ChapterCompleteHelper.removeAllOkMarks(saveDir);
                            _emitPartialProgress(
                                taskId,
                                albumDetail,
                                downloadedPhotoIds,
                                partialDownloadedPhotoIds,
                                totalImages,
                            );
                        }
                        await reportProgress();
                    }
                    finally
                    {
                        semaphore.release();
                    }
                }
                return saveDir;
            }

            // 把所有章节的下载任务全部派发，由信号量统一限流
            for (var epIdx = 0; epIdx < albumDetail.episodes.length; epIdx++)
            {
                if (cancelToken.isCancelled) break;
                final episode = albumDetail.episodes[epIdx];
                final detail = detailByPhotoId[episode.photoId];
                if (detail == null) continue;
                futures.add(downloadEpisode(episode, detail).then((dir)
                {
                    if (dir.isNotEmpty) lastSaveDir = dir;
                    return dir;
                }));
            }

            await Future.wait(futures);

            // 处理暂停：状态置为 paused，方便 UI 区分；不清空本地文件
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
                final localCoverPath = await _downloadAlbumCover(
                    albumId,
                    '$albumDir${Platform.pathSeparator}cover.jpg',
                    fallbackFirstImage: lastSaveDir.isNotEmpty
                        ? '$lastSaveDir${Platform.pathSeparator}00001.jpg'
                        : '',
                );
                final localPath = albumDir;
                // 一并持久化每个章节的 scrambleId + pageArr，
                // 阅读器离线打开时可跳过 getPhotoDetail / getScrambleId 网络请求
                final chapters = <String, ChapterMetadata>{};
                for (final episode in albumDetail.episodes)
                {
                    final detail = detailByPhotoId[episode.photoId];
                    if (detail == null) continue;
                    chapters[episode.photoId] = ChapterMetadata(
                        photoId: episode.photoId,
                        index: episode.index,
                        name: episode.name,
                        scrambleId: scrambleIds[episode.photoId] ?? 0,
                        pageArr: detail.pageArr,
                    );
                }
                await LibraryStorage.saveAlbumMetadata(
                    albumDir, albumDetail,
                    chapters: chapters,
                );
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0,
                    downloadedPhotoIds.toList(),
                    author: albumDetail.author,
                    pageCount: totalImages,
                    episodeCount: albumDetail.episodes.length,
                    localCoverPath: localCoverPath,
                    localPath: localPath,
                );
            }
        }
        catch (e)
        {
            // 暂停优先于异常：cancel 后已派发任务会抛 CancelException
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
            // paused 状态保留在 _pausedTasks 中，由 resume 移除
        }
    }

    /// 判断指定章节是否所有页都已完成（用于增量入书架）
    bool _isEpisodeComplete(
        int totalPages,
        String photoId,
        Set<_AlbumImageKey> completedImages,
    )
    {
        for (var i = 0; i < totalPages; i++)
        {
            if (!completedImages.contains(_AlbumImageKey(photoId, i))) return false;
        }
        return true;
    }

    /// 单图是否已存在且有效（异步，避免阻塞事件循环）
    ///
    /// 【性能优化 P2】
    /// - 优先检查章节级 `.complete`：存在则整章有效，无需逐页 stat
    /// - 章节未完成时回退到单页 `.ok` 检查（兼容边下边看场景）
    Future<bool> _isImageDownloaded(String saveDir, int pageIndex) async
    {
        final savePath = '$saveDir${Platform.pathSeparator}${(pageIndex + 1).toString().padLeft(5, '0')}.jpg';
        // 1. 章节级 .complete 命中 → 整章有效
        if (await ChapterCompleteHelper.isChapterComplete(saveDir))
        {
            return await FileExistenceCache.fileExists(savePath);
        }
        // 2. 回退到单页 .ok 检查
        final okPath = '$savePath.ok';
        final saveExists = await FileExistenceCache.fileExists(savePath);
        if (!saveExists) return false;
        return await FileExistenceCache.fileExists(okPath);
    }

    /// 发送增量进度事件（用于 library 实时同步已完成的章节）
    void _emitPartialProgress(
        String taskId,
        AlbumDetail albumDetail,
        Set<String> downloadedPhotoIds,
        Set<String> partialDownloadedPhotoIds,
        int totalImages,
    )
    {
        final stats = _taskStats[taskId];
        final speed = stats != null
            ? DownloadServiceStatusEmitter._formatSpeed(stats.getSpeed())
            : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: 0,
            total: totalImages,
            speed: speed,
            progress: 0.0,
            status: 'running',
            message: '已下载 ${downloadedPhotoIds.length} / ${albumDetail.episodes.length} 章',
            downloadedPhotoIds: downloadedPhotoIds.toList(),
            partialDownloadedPhotoIds: partialDownloadedPhotoIds.toList(),
            author: albumDetail.author,
            pageCount: totalImages,
            episodeCount: albumDetail.episodes.length,
        ));
    }

    /// 下载本子封面并保存为 cover.jpg
    Future<String> _downloadAlbumCover(
        String albumId,
        String savePath, {
        String fallbackFirstImage = '',
    }) async
    {
        try
        {
            final dir = File(savePath).parent;
            if (!await dir.exists())
            {
                await dir.create(recursive: true);
            }
        }
        catch (_)
        {
        }

        for (final size in const ['_3x4', '_2x3', ''])
        {
            final url = _client.getAlbumCoverUrl(albumId, size: size);
            if (await _fetchBytesToFile(url, savePath)) return savePath;
        }

        if (fallbackFirstImage.isNotEmpty)
        {
            final src = File(fallbackFirstImage);
            if (await src.exists())
            {
                try
                {
                    await src.copy(savePath);
                    return savePath;
                }
                catch (_)
                {
                    return fallbackFirstImage;
                }
            }
        }
        return '';
    }

    /// 从 URL 拉取字节并写入文件
    Future<bool> _fetchBytesToFile(String url, String savePath) async
    {
        try
        {
            final resp = await _client.dio.get<List<int>>(
                url,
                options: Options(
                    responseType: ResponseType.bytes,
                    receiveTimeout: const Duration(seconds: 15),
                    sendTimeout: const Duration(seconds: 10),
                ),
            );
            final code = resp.statusCode ?? 0;
            final data = resp.data;
            if (code >= 200 && code < 300 && data != null && data.isNotEmpty)
            {
                await File(savePath).writeAsBytes(data, flush: true);
                return true;
            }
        }
        catch (_)
        {
        }
        return false;
    }
}

/// album 全任务并发时定位"已完成的某张图"的 key
class _AlbumImageKey
{
    final String photoId;
    final int pageIndex;
    const _AlbumImageKey(this.photoId, this.pageIndex);

    @override
    bool operator ==(Object other) =>
        other is _AlbumImageKey &&
        other.photoId == photoId &&
        other.pageIndex == pageIndex;

    @override
    int get hashCode => Object.hash(photoId, pageIndex);
}
