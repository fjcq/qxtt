part of 'download_service.dart';

/// 负责单章（photo）下载
extension DownloadServicePhotoHandler on DownloadService
{
    /// 确保指定章节已下载（统一阅读入口）
    ///
    /// 【统一阅读架构】
    /// 所有阅读入口（在线浏览 / 下载管理 / 书架）进入阅读时统一调用，
    /// 让章节要么已下载完成，要么自动创建下载任务并在后台执行。
    ///
    /// 行为：
    /// 1. 计算章节本地保存目录
    /// 2. 检查 `.complete` 标记，命中则直接返回路径
    /// 3. 查询已有活跃任务（pending/running/paused），命中则复用，不重复创建
    /// 4. 否则创建新任务（`source='reading'`），fire-and-forget 启动 [downloadPhoto]
    /// 5. 立即返回章节目录路径，调用方通过订阅 [onProgress] 感知进度
    ///
    /// 不阻塞调用：章节未下载时也立即返回路径，阅读器渲染时未下载页
    /// 通过 `WaitingPagePlaceholder` 显示占位，下载完成后通过事件自动刷新。
    ///
    /// - [photoId] 章节 ID
    /// - [albumId] 作品 ID
    /// - [title] 作品标题（用于本地目录命名，为空时回退 photoId）
    /// - [episodeIndex] 章节序号
    /// - [episodeName] 章节名
    ///
    /// 返回：章节本地目录路径（已存在或新建任务的保存目录）
    Future<String> ensureChapterDownloaded({
        required String photoId,
        required String albumId,
        required String title,
        required String episodeIndex,
        required String episodeName,
    }) async
    {
        // 1. 解析下载根目录
        final downloadDir = _downloadDir.isEmpty
            ? await PathHelper.getDownloadDir()
            : _downloadDir;

        // 2. 计算章节保存目录（与 downloadPhoto 完全一致）
        final String saveDir;
        if (title.isNotEmpty && episodeIndex.isNotEmpty)
        {
            final safeAlbumTitle = DownloadService._sanitizeFileName(title);
            final safeEpisodeIndex = DownloadService._sanitizeFileName(episodeIndex);
            saveDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle'
                '${Platform.pathSeparator}$safeEpisodeIndex';
        }
        else
        {
            saveDir = '$downloadDir${Platform.pathSeparator}$photoId';
        }

        // 3. 章节已完成 → 直接返回路径，不创建任务
        if (await ChapterCompleteHelper.isChapterComplete(saveDir))
        {
            return saveDir;
        }

        // 4. 查询已有活跃任务（pending/running/paused），命中则复用
        final allTasks = await _taskDao.getAllTasks();
        const activeStatuses = {'pending', 'running', 'paused'};
        final existing = allTasks
            .where((t) =>
                t.taskType == 'photo' &&
                t.jmId == photoId &&
                activeStatuses.contains(t.status))
            .firstOrNull;
        if (existing != null)
        {
            // 已存在活跃任务，让阅读器复用其进度，无需重复创建
            return saveDir;
        }

        // 5. 创建新任务（source=reading），fire-and-forget 启动下载
        final task = await createTask(
            'photo',
            photoId,
            albumId: albumId,
            albumTitle: title,
            episodeIndex: episodeIndex,
            episodeName: episodeName,
            source: 'reading',
        );

        // 异步启动下载，不阻塞调用方；失败仅记录日志
        // ignore: discarded_futures
        downloadPhoto(task).catchError((Object e) {
            // 静默处理：状态已由 downloadPhoto 内部写入 taskDao
        });

        return saveDir;
    }

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
        // 已完成的页索引集合（含续传已有），供暂停/失败/完成事件组装章节级进度
        var donePages = <int>{};
        // 章节总页数（详情获取成功后填充；失败发生在获取前时保持 0）
        var totalImages = 0;

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取章节详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取章节详情', 0.0, photoId: photoId);

            final photoDetail = await _client.getPhotoDetail(photoId);
            // 优先使用 APP API 响应自带的 scramble_id，仅缺失时走 HTML 兜底
            final scrambleId = photoDetail.scrambleId != 0
                ? photoDetail.scrambleId
                : await _client.getScrambleId(photoId);

            if (cancelToken.isCancelled) return;

            totalImages = photoDetail.pageArr.length;

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
                if (await _isImageDownloaded(saveDir, i)) completed.add(i);
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
                photoId: photoId,
                chapterProgress: {
                    photoId: ChapterProgress(
                        completed: completed.length,
                        total: totalImages,
                    ),
                },
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

            donePages = await _runConcurrentImageDownload(
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
                _emitStatus(
                    taskId, 'paused', '已暂停', 0.0,
                    photoId: photoId,
                    chapterProgress: {
                        photoId: ChapterProgress(
                            completed: donePages.length,
                            total: totalImages,
                        ),
                    },
                );
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
                    // 一并持久化 scrambleId + pageArr，
                    // 阅读器离线打开时可跳过 getPhotoDetail / getScrambleId 网络请求
                    await LibraryStorage.saveChapterMetadata(
                        albumDir,
                        photoId: photoId,
                        index: task.episodeIndex,
                        name: task.episodeName,
                        scrambleId: scrambleId,
                        pageArr: photoDetail.pageArr,
                        albumId: task.albumId,
                        title: task.albumTitle,
                    );
                }
                // 【性能优化 P2】单章下载完成时写章节级 .complete，
                // 并删除该章节所有 .ok 碎片文件
                await ChapterCompleteHelper.markChapterComplete(
                    saveDir, photoDetail.pageArr.length,
                );
                await ChapterCompleteHelper.removeAllOkMarks(saveDir);
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0, [photoId],
                    localCoverPath: coverPath,
                    localPath: saveDir,
                    photoId: photoId,
                    chapterProgress: {
                        photoId: ChapterProgress(
                            completed: donePages.length,
                            total: totalImages,
                        ),
                    },
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
                _emitStatus(
                    taskId, 'paused', '已暂停', 0.0,
                    photoId: photoId,
                    chapterProgress: {
                        photoId: ChapterProgress(
                            completed: donePages.length,
                            total: totalImages,
                        ),
                    },
                );
            }
            else if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'failed', '下载失败: $e', 0.0,
                );
                _emitStatus(
                    taskId, 'failed', '下载失败: $e', 0.0,
                    photoId: photoId,
                    chapterProgress: {
                        photoId: ChapterProgress(
                            completed: donePages.length,
                            total: totalImages,
                        ),
                    },
                );
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
    ///
    /// 返回：已完成（含续传已有）的页索引集合，供调用方在
    /// 暂停/失败/完成事件中组装章节级进度
    Future<Set<int>> _runConcurrentImageDownload({
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
                photoId: photoId,
                chapterProgress: {
                    photoId: ChapterProgress(
                        completed: doneCount,
                        total: totalImages,
                    ),
                },
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
                // 【统一阅读】单页完成后广播事件，阅读器订阅后可精确刷新对应页
                final doneCount = completed.length;
                final progress = totalImages > 0 ? doneCount / totalImages : 0.0;
                _emitPageCompleted(
                    taskId, photoId, filename, doneCount, totalImages, progress,
                );
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
        return completed;
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
