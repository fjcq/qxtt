part of 'download_service.dart';

/// 负责整本（album）下载
extension DownloadServiceAlbumHandler on DownloadService
{
    /// 下载整本漫画
    Future<void> downloadAlbum(String taskId, String albumId) async
    {
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        final downloadedPhotoIds = <String>[];

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取详情', 0.0);

            final albumDetail = await _client.getAlbumDetail(albumId);

            if (cancelToken.isCancelled) return;

            final photoDetails = <PhotoDetail>[];
            var totalImages = 0;

            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) return;

                final photoDetail = await _client.getPhotoDetail(episode.photoId);
                photoDetails.add(photoDetail);
                totalImages += photoDetail.pageArr.length;
            }

            if (albumDetail.episodes.isNotEmpty)
            {
                await _taskDao.updateFirstPhotoId(
                    taskId, albumDetail.episodes.first.photoId,
                );
            }

            await _taskDao.updateTaskProgress(taskId, 0, totalImages, 0.0);
            _emitProgress(taskId, 0, totalImages, 0.0, 'running', '正在下载');

            var completedImages = 0;
            final safeAlbumTitle = DownloadService._sanitizeFileName(albumDetail.name);
            final downloadDir = _downloadDir.isEmpty
                ? await PathHelper.getDownloadDir()
                : _downloadDir;
            String lastSaveDir = '';

            for (var epIdx = 0; epIdx < albumDetail.episodes.length; epIdx++)
            {
                if (cancelToken.isCancelled) break;

                final episode = albumDetail.episodes[epIdx];
                final photoDetail = photoDetails[epIdx];
                final scrambleId = await _client.getScrambleId(episode.photoId);

                if (cancelToken.isCancelled) break;

                final safeEpisodeIndex = DownloadService._sanitizeFileName(episode.index);
                final saveDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle${Platform.pathSeparator}$safeEpisodeIndex';
                await Directory(saveDir).create(recursive: true);
                lastSaveDir = saveDir;

                for (var i = 0; i < photoDetail.pageArr.length; i++)
                {
                    if (cancelToken.isCancelled) break;

                    final filename = photoDetail.pageArr[i];
                    final savePath = '$saveDir/${(i + 1).toString().padLeft(5, '0')}.jpg';

                    try
                    {
                        final downloaded = await _client.downloadImageToFile(
                            episode.photoId,
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
                            final aid = int.tryParse(episode.photoId) ?? 0;
                            final num = JmImage.getSegmentationNum(
                                scrambleId, aid, filename,
                            );
                            DownloadService._logger.i('[解密] $filename: '
                                'scrambleId=$scrambleId, aid=$aid, '
                                'photoId=${episode.photoId}, num=$num, '
                                'downloaded=$downloaded, '
                                'forceDecode=$needDecodeAnyway');
                            try
                            {
                                final exePath = Platform.resolvedExecutable;
                                final exeDir = exePath.substring(0, exePath.lastIndexOf('\\'));
                                final f = File('$exeDir\\DOWNLOAD_DIAG.txt');
                                f.writeAsStringSync(
                                    'photoId=${episode.photoId} filename=$filename '
                                    'scrambleId=$scrambleId aid=$aid num=$num '
                                    'downloaded=$downloaded forceDecode=$needDecodeAnyway\n',
                                    mode: FileMode.append,
                                );
                            }
                            catch (_) {}
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

                if (!downloadedPhotoIds.contains(episode.photoId))
                {
                    downloadedPhotoIds.add(episode.photoId);
                }
            }

            if (!cancelToken.isCancelled)
            {
                await _taskDao.updateTaskStatus(
                    taskId, 'completed', '下载完成', 1.0,
                );
                final albumDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle';
                final localCoverPath =
                    await _downloadAlbumCover(
                        albumId,
                        '$albumDir${Platform.pathSeparator}cover.jpg',
                        fallbackFirstImage: lastSaveDir.isNotEmpty
                            ? '$lastSaveDir${Platform.pathSeparator}00001.jpg'
                            : '',
                    );
                final localPath = albumDir;
                await LibraryStorage.saveAlbumMetadata(albumDir, albumDetail);
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0, downloadedPhotoIds,
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
