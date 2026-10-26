part of 'download_service.dart';

/// 负责整本（album）下载
extension DownloadServiceAlbumHandler on DownloadService
{
    /// 下载整本漫画
    ///
    /// 流程：
    /// 1. 拉取本子详情与所有章节的 photoDetail
    /// 2. **章节串行 + 章节内图片并发**：按章节顺序逐章下载，单章内的所有图片
    ///    一起抢 [_imageThreadCount] 个许可并发下载。前面的章节先完成，
    ///    用户可边下边读；下载速度不受影响（单章即可吃满并发上限）。
    ///    取消时停止派发后续章节，已开始的图片会自然结束。
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
        // 本子详情引用：提升到 try 外供 catch 块组装章节进度（获取失败时为 null）
        AlbumDetail? albumDetailRef;
        // 章节详情映射与已完成图片集合：提升到 try 外供 catch 块使用
        final detailByPhotoId = <String, PhotoDetail>{};
        final completedImages = <_AlbumImageKey>{};
        // 总页数：提升到 try 外，供 catch 块按真实进度写回状态
        var totalImages = 0;

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取详情', 0.0);

            final albumDetail = await _client.getAlbumDetail(albumId);
            // 同步到外层引用（catch 块访问提升后的可空变量）
            albumDetailRef = albumDetail;

            if (cancelToken.isCancelled) return;

            // 先并行获取所有章节的详情 + scrambleId，加速启动
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

            // 复用已存在的本子目录：本子更新后书名可能变化，
            // 若按新书名新建目录会导致已下载章节全部重下
            final defaultAlbumDir =
                '$downloadDir${Platform.pathSeparator}$safeAlbumTitle';
            final albumDir = await _resolveAlbumDir(
                downloadDir, albumId, defaultAlbumDir,
            );
            // 旧章节目录映射（photoId → 实际目录），兼容章节序号变化
            final legacyEpisodeDirs = await _loadLegacyEpisodeDirs(albumDir);

            /// 章节实际保存目录：优先复用旧目录，避免已下载章节重下
            String episodeDirOf(Episode episode)
            {
                final legacyDir = legacyEpisodeDirs[episode.photoId];
                if (legacyDir != null && legacyDir.isNotEmpty)
                {
                    return legacyDir;
                }
                final safeEpisodeIndex =
                    DownloadService._sanitizeFileName(episode.index);
                return '$albumDir${Platform.pathSeparator}$safeEpisodeIndex';
            }

            // 断点续传：扫描本地已有图片，纳入初始完成集合
            // 这样进度条与持久化的 currentImage 不会因为续传而从 0 跳到 N
            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) break;
                final detail = detailByPhotoId[episode.photoId];
                if (detail == null) continue;
                final saveDir = episodeDirOf(episode);
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
                chapterProgress: _buildChapterProgress(
                    albumDetail, detailByPhotoId, completedImages,
                ),
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
                    detailByPhotoId,
                    completedImages,
                );
            }

            // 并发信号量：章节之间串行，章节内的图片共用此信号量并发下载
            final semaphore = DownloadSemaphore(_imageThreadCount);
            final rotator = DomainRotator(_client.imageDomainList.length);
            // 记录第一个可用章节目录（最早章节），供封面下载失败时兜底
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
                    chapterProgress: _buildChapterProgress(
                        albumDetail, detailByPhotoId, completedImages,
                    ),
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
                final saveDir = episodeDirOf(episode);
                await Directory(saveDir).create(recursive: true);
                final aid = int.tryParse(episode.photoId) ?? 0;

                // 章节内并发：本章所有图片任务一起派发，由信号量统一限流，
                // 单章即可吃满 [_imageThreadCount] 并发上限
                final pageFutures = <Future<void>>[];
                for (var i = 0; i < detail.pageArr.length; i++)
                {
                    pageFutures.add(() async
                    {
                        onPauseSignal();
                        if (cancelToken.isCancelled) return;
                        final pageIndex = i;
                        // 续传：本地已有且 .ok 标记则跳过
                        if (completedImages.contains(_AlbumImageKey(episode.photoId, pageIndex)))
                        {
                            return;
                        }
                        final filename = detail.pageArr[pageIndex];
                        await semaphore.acquire();
                        try
                        {
                            if (cancelToken.isCancelled) return;
                            final result = await downloadOneImageWithDecode(
                                client: _client,
                                cancelToken: cancelToken,
                                photoId: episode.photoId,
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
                            // 仅成功的页才计入完成集合：失败的页保持未完成，
                            // 续传时会被重新下载，进度条也不会虚高
                            if (!result.success)
                            {
                                await reportProgress();
                                return;
                            }
                            completedImages.add(_AlbumImageKey(episode.photoId, pageIndex));
                            // 边下边看：只要有一张图下载成功，立即把该章节加入部分可读集合
                            if (partialDownloadedPhotoIds.add(episode.photoId))
                            {
                                _emitPartialProgress(
                                    taskId,
                                    albumDetail,
                                    downloadedPhotoIds,
                                    partialDownloadedPhotoIds,
                                    totalImages,
                                    detailByPhotoId,
                                    completedImages,
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
                                    detailByPhotoId,
                                    completedImages,
                                );
                            }
                            await reportProgress();
                        }
                        finally
                        {
                            semaphore.release();
                        }
                    }());
                }
                await Future.wait(pageFutures);
                return saveDir;
            }

            // 章节串行：按顺序逐章下载，前面的章节先完成，便于用户边下边读；
            // 单章内部已并发派发图片，整体下载速度不受影响
            for (var epIdx = 0; epIdx < albumDetail.episodes.length; epIdx++)
            {
                if (cancelToken.isCancelled) break;
                final episode = albumDetail.episodes[epIdx];
                final detail = detailByPhotoId[episode.photoId];
                if (detail == null) continue;
                final dir = await downloadEpisode(episode, detail);
                // 记录第一个可用章节目录，供封面下载失败时兜底（即最早章节的第一页）
                if (dir.isNotEmpty && lastSaveDir.isEmpty) lastSaveDir = dir;
            }

            // 处理暂停：状态置为 paused，方便 UI 区分；不清空本地文件
            // progress 使用真实完成比例，避免暂停后进度条归零
            if (wasPaused || cancelToken.isCancelled)
            {
                final pausedProgress = totalImages > 0
                    ? completedImages.length / totalImages
                    : 0.0;
                await _taskDao.updateTaskStatus(
                    taskId, 'paused', '已暂停', pausedProgress,
                );
                _emitStatus(
                    taskId, 'paused', '已暂停', pausedProgress,
                    chapterProgress: _buildChapterProgress(
                        albumDetail, detailByPhotoId, completedImages,
                    ),
                );
                return;
            }

            // 部分图片下载失败：不标记完成，保留已下载进度供用户重试补页
            if (completedImages.length < totalImages)
            {
                final partialProgress = totalImages > 0
                    ? completedImages.length / totalImages
                    : 0.0;
                final message =
                    '部分图片下载失败（${completedImages.length}/$totalImages）';
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', message, partialProgress,
                );
                _emitStatus(
                    taskId, 'failed', message, partialProgress,
                    chapterProgress: _buildChapterProgress(
                        albumDetail, detailByPhotoId, completedImages,
                    ),
                );
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
                // 记录章节实际目录名，供下次更新时按真实目录定位旧章节
                final episodeDirs = <String, String>{};
                final albumDirPrefix = '$albumDir${Platform.pathSeparator}';
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
                    final dir = episodeDirOf(episode);
                    if (dir.startsWith(albumDirPrefix))
                    {
                        episodeDirs[episode.photoId] =
                            dir.substring(albumDirPrefix.length);
                    }
                }
                await LibraryStorage.saveAlbumMetadata(
                    albumDir, albumDetail,
                    chapters: chapters,
                    episodeDirs: episodeDirs,
                );
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0,
                    downloadedPhotoIds.toList(),
                    author: albumDetail.author,
                    pageCount: totalImages,
                    episodeCount: albumDetail.episodes.length,
                    localCoverPath: localCoverPath,
                    localPath: localPath,
                    chapterProgress: _buildChapterProgress(
                        albumDetail, detailByPhotoId, completedImages,
                    ),
                );
            }
        }
        catch (e)
        {
            // catch 块的章节进度：详情获取成功时组装各章最后进度，否则留空
            final chapterProgress = albumDetailRef != null
                ? _buildChapterProgress(albumDetailRef, detailByPhotoId, completedImages)
                : const <String, ChapterProgress>{};
            // 暂停优先于异常：cancel 后已派发任务会抛 CancelException
            if (wasPaused || _pausedTasks.contains(taskId))
            {
                final pausedProgress = totalImages > 0
                    ? completedImages.length / totalImages
                    : 0.0;
                await _taskDao.updateTaskStatus(
                    taskId, 'paused', '已暂停', pausedProgress,
                );
                _emitStatus(
                    taskId, 'paused', '已暂停', pausedProgress,
                    chapterProgress: chapterProgress,
                );
            }
            else if (!cancelToken.isCancelled)
            {
                final failedProgress = totalImages > 0
                    ? completedImages.length / totalImages
                    : 0.0;
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', '下载失败: $e', failedProgress,
                );
                _emitStatus(
                    taskId, 'failed', '下载失败: $e', failedProgress,
                    chapterProgress: chapterProgress,
                );
            }
        }
        finally
        {
            _cancelTokens.remove(taskId);
            _taskStats.remove(taskId);
            // paused 状态保留在 _pausedTasks 中，由 resume 移除
        }
    }

    /// 解析本子实际使用的本地根目录
    ///
    /// 优先复用同名目录；同名目录不存在时扫描下载根目录下的一级子目录，
    /// 按 `.jm_album_meta.json` 中的 albumId 命中旧目录，
    /// 避免本子更新后改名导致整本从头下载。
    Future<String> _resolveAlbumDir(
        String downloadDir,
        String albumId,
        String defaultAlbumDir,
    ) async
    {
        if (await Directory(defaultAlbumDir).exists())
        {
            return defaultAlbumDir;
        }
        if (albumId.isEmpty) return defaultAlbumDir;
        try
        {
            await for (final entity in Directory(downloadDir).list(
                followLinks: false,
            ))
            {
                if (entity is! Directory) continue;
                final metaFile = File(
                    '${entity.path}${Platform.pathSeparator}.jm_album_meta.json',
                );
                if (!await metaFile.exists()) continue;
                try
                {
                    final json = jsonDecode(await metaFile.readAsString())
                        as Map<String, dynamic>;
                    if (json['albumId']?.toString() == albumId)
                    {
                        return entity.path;
                    }
                }
                catch (_)
                {
                    // 单个元数据损坏不影响其它目录扫描
                }
            }
        }
        catch (_)
        {
            // 下载根目录不可读时回退默认目录
        }
        return defaultAlbumDir;
    }

    /// 加载旧章节目录映射（photoId → 已存在的目录）
    ///
    /// 本子更新后章节序号可能变化，旧章节仍保存在旧目录中。
    /// 仅保留实际存在的目录，避免指向幽灵路径导致重复下载。
    Future<Map<String, String>> _loadLegacyEpisodeDirs(String albumDir) async
    {
        final (_, dirs, _) =
            await AlbumMetadataStorage.loadAlbumMetadataWithChapters(albumDir);
        if (dirs.isEmpty) return const <String, String>{};
        final valid = <String, String>{};
        for (final entry in dirs.entries)
        {
            if (await Directory(entry.value).exists())
            {
                valid[entry.key] = entry.value;
            }
        }
        return valid;
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
    ///
    /// 同时携带章节级进度映射，详情页据此渲染每章节的独立进度条
    void _emitPartialProgress(
        String taskId,
        AlbumDetail albumDetail,
        Set<String> downloadedPhotoIds,
        Set<String> partialDownloadedPhotoIds,
        int totalImages,
        Map<String, PhotoDetail> detailByPhotoId,
        Set<_AlbumImageKey> completedImages,
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
            chapterProgress: _buildChapterProgress(
                albumDetail, detailByPhotoId, completedImages,
            ),
        ));
    }

    /// 从已完成图片集合折叠出章节级进度映射
    ///
    /// 遍历本子所有章节，结合 [detailByPhotoId] 的总页数与
    /// [completedImages] 中按章节统计的已完成图片数，
    /// 组装 photoId → [ChapterProgress] 映射供详情页渲染
    Map<String, ChapterProgress> _buildChapterProgress(
        AlbumDetail albumDetail,
        Map<String, PhotoDetail> detailByPhotoId,
        Set<_AlbumImageKey> completedImages,
    )
    {
        // 按章节折叠已完成图片数
        final perChapterDone = <String, int>{};
        for (final key in completedImages)
        {
            perChapterDone[key.photoId] = (perChapterDone[key.photoId] ?? 0) + 1;
        }
        // 组装每章节的进度（总页数取自章节详情）
        final result = <String, ChapterProgress>{};
        for (final episode in albumDetail.episodes)
        {
            final detail = detailByPhotoId[episode.photoId];
            if (detail == null) continue;
            result[episode.photoId] = ChapterProgress(
                completed: perChapterDone[episode.photoId] ?? 0,
                total: detail.pageArr.length,
            );
        }
        return result;
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
