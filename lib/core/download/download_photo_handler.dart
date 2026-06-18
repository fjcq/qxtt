part of 'download_service.dart';

/// 负责单章（photo）下载
extension DownloadServicePhotoHandler on DownloadService
{
    /// 下载单个章节
    Future<void> downloadPhoto(DownloadTaskModel task) async
    {
        final taskId = task.taskId;
        final photoId = task.jmId;
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取章节详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取章节详情', 0.0);

            final photoDetail = await _client.getPhotoDetail(photoId);
            final scrambleId = await _client.getScrambleId(photoId);

            if (cancelToken.isCancelled) return;

            final totalImages = photoDetail.pageArr.length;
            await _taskDao.updateTaskProgress(taskId, 0, totalImages, 0.0);
            _emitProgress(taskId, 0, totalImages, 0.0, 'running', '正在下载');

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

            var completedImages = 0;

            for (var i = 0; i < photoDetail.pageArr.length; i++)
            {
                if (cancelToken.isCancelled) break;

                final filename = photoDetail.pageArr[i];
                final savePath = '$saveDir/${(i + 1).toString().padLeft(5, '0')}.jpg';

                try
                {
                    final downloaded = await _client.downloadImageToFile(
                        photoId,
                        filename,
                        savePath,
                        cancelToken: cancelToken,
                    );

                    final f = File(savePath);
                    final needDecodeAnyway = !downloaded &&
                        f.existsSync() &&
                        JmImage.isUndecodedWebp(savePath);

                    if (downloaded)
                    {
                        if (f.existsSync())
                        {
                            _taskStats[taskId]?.addBytes(f.lengthSync());
                        }
                    }

                    if (downloaded || needDecodeAnyway)
                    {
                        final aid = int.tryParse(photoId) ?? 0;
                        final num = JmImage.getSegmentationNum(
                            scrambleId, aid, filename,
                        );
                        DownloadService._logger.i('[解密] $filename: '
                            'scrambleId=$scrambleId, aid=$aid, '
                            'photoId=$photoId, num=$num, '
                            'downloaded=$downloaded, '
                            'forceDecode=$needDecodeAnyway');
                        await _decodeAndSave(
                            savePath,
                            scrambleId,
                            aid,
                            filename,
                        );
                    }
                }
                catch (e)
                {
                    continue;
                }

                completedImages++;
                final progress = totalImages > 0 ? completedImages / totalImages : 0.0;
                await _taskDao.updateTaskProgress(
                    taskId, completedImages, totalImages, progress,
                );
                _emitProgress(
                    taskId, completedImages, totalImages, progress,
                    'running', '正在下载',
                );
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
            if (!cancelToken.isCancelled)
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
