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
import '../../utils/path_helper.dart';

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

    /// 任务状态（running/completed/failed/cancelled）
    final String status;

    /// 状态消息
    final String message;

    /// 本次任务涉及并已成功下载的 photoId 列表
    /// 仅在 status='completed' 时填充
    final List<String> downloadedPhotoIds;

    /// 本子作者（仅 album 任务且完成时填充）
    final String author;

    /// 本子页数（仅 album 任务且完成时填充）
    final int pageCount;

    /// 本子章节数（仅 album 任务且完成时填充）
    final int episodeCount;

    /// 本子本地封面路径（仅 album 任务且完成时填充）
    final String localCoverPath;

    /// 本子本地下载根目录（仅 album 任务且完成时填充）
    final String localPath;

    const DownloadProgressEvent({
        required this.taskId,
        required this.current,
        required this.total,
        required this.speed,
        required this.progress,
        required this.status,
        required this.message,
        this.downloadedPhotoIds = const [],
        this.author = '',
        this.pageCount = 0,
        this.episodeCount = 0,
        this.localCoverPath = '',
        this.localPath = '',
    });
}

/// 下载服务 - 管理并发下载任务
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
    }) async
    {
        const uuid = Uuid();
        final task = DownloadTaskModel()
            ..taskId = uuid.v4()
            ..taskType = type
            ..jmId = jmId
            ..albumId = albumId ?? (type == 'album' ? jmId : '')
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

        // 记录本次下载成功完成的所有章节 photoId
        final downloadedPhotoIds = <String>[];

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取详情', 0.0);

            // 获取本子详情
            final albumDetail = await _client.getAlbumDetail(albumId);

            if (cancelToken.isCancelled) return;

            // 预获取所有章节详情，计算总图片数
            final photoDetails = <PhotoDetail>[];
            var totalImages = 0;

            for (final episode in albumDetail.episodes)
            {
                if (cancelToken.isCancelled) return;

                final photoDetail = await _client.getPhotoDetail(episode.photoId);
                photoDetails.add(photoDetail);
                totalImages += photoDetail.pageArr.length;
            }

            // 记录第一话 photoId 用于"立即观看"
            if (albumDetail.episodes.isNotEmpty)
            {
                await _taskDao.updateFirstPhotoId(
                    taskId, albumDetail.episodes.first.photoId,
                );
            }

            await _taskDao.updateTaskProgress(taskId, 0, totalImages, 0.0);
            _emitProgress(taskId, 0, totalImages, 0.0, 'running', '正在下载');

            // 遍历章节下载所有图片
            var completedImages = 0;
            final safeAlbumTitle = _sanitizeFileName(albumDetail.name);
            // 计算本子本地下载根目录（在循环外计算一次，供完成事件携带）
            final downloadDir = _downloadDir.isEmpty
                ? await PathHelper.getDownloadDir()
                : _downloadDir;
            // 最后一个章节的 saveDir（用于生成 cover.jpg 路径）
            String lastSaveDir = '';

            for (var epIdx = 0; epIdx < albumDetail.episodes.length; epIdx++)
            {
                if (cancelToken.isCancelled) break;

                final episode = albumDetail.episodes[epIdx];
                final photoDetail = photoDetails[epIdx];
                final scrambleId = await _client.getScrambleId(episode.photoId);

                if (cancelToken.isCancelled) break;

                final safeEpisodeIndex = _sanitizeFileName(episode.index);
                final saveDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle${Platform.pathSeparator}$safeEpisodeIndex';
                await Directory(saveDir).create(recursive: true);
                lastSaveDir = saveDir;

                // 下载该章节的所有图片
                for (var i = 0; i < photoDetail.pageArr.length; i++)
                {
                    if (cancelToken.isCancelled) break;

                    final filename = photoDetail.pageArr[i];
                    final savePath = '$saveDir/${(i + 1).toString().padLeft(5, '0')}.jpg';

                    try
                    {
                        // 使用流式下载：已存在则跳过（返回 false），否则按需 Range 续传
                        final downloaded = await _client.downloadImageToFile(
                            episode.photoId,
                            filename,
                            savePath,
                            cancelToken: cancelToken,
                        );

                        // 重要：如果文件已存在但仍是未解密的加密图（说明旧 build
                        // 下载时解密失败被回退），即使 downloaded=false 也要重新解密，
                        // 否则用户永远只能看到未解密的图。
                        // 判定依据由 isUndecodedWebp 提供——它检查 RIFF 头和 .ok 标记。
                        final f = File(savePath);
                        final needDecodeAnyway = !downloaded &&
                            f.existsSync() &&
                            JmImage.isUndecodedWebp(savePath);

                        // 注意：旧版"旧加密图清理"分支（无 .ok + num=0 删旧文件重下）
                        // 已废弃。现在无论 scrambleId 是 0 还是具体值，每次下载后
                        // 都会调 _decodeAndSave 把 webp 转 jpg（num=0 时只转码不解密），
                        // 不再需要"删除旧文件重下"来强制走 webp→jpg 转码。

                        if (downloaded)
                        {
                            // 仅在新下载/续传完成时累计字节
                            if (f.existsSync())
                            {
                                _taskStats[taskId]?.addBytes(f.lengthSync());
                            }
                        }

                        // 解密条件：downloaded=true（新下载/续传完成）
                        //            或 needDecodeAnyway（文件是 WEBP，需补做解密）
                        if (downloaded || needDecodeAnyway)
                        {
                            // aid 必须是 photoId（章节ID），与 Python 参考实现的
                            // parse_to_jm_id(url) 从 /media/photos/{photoId}/{filename}
                            // 提取的 ID 一致，用于 md5(aid+filename) 推算 num。
                            // 之前误用 albumId（本子ID）会导致 num 计算错误，
                            // 图片呈现为另一种错位（看起来像未解密）。
                            //
                            // 注意：即使 scrambleId == 0（getScrambleId 没匹配到
                            // var scramble_id = (\d+) 时的 fallback）也必须调
                            // _decodeAndSave。_dio.download 把 webp 字节流直接
                            // 存到 .jpg 文件里——文件内容是 webp 但扩展名是 jpg，
                            // 图片查看器用 JPEG 解码器解 webp 会得到错乱图。
                            // 这种情况 _decodeAndSave 内部 getSegmentationNum(0,...)
                            // 返回 0，跳过行重排，但仍会做 platformDecode(webp→RGBA)
                            // 再 encodeJpg(RGBA→jpg)，输出真正的 jpg 字节。
                            final aid = int.tryParse(episode.photoId) ?? 0;
                            final num = JmImage.getSegmentationNum(
                                scrambleId, aid, filename,
                            );
                            _logger.i('[解密] $filename: '
                                'scrambleId=$scrambleId, aid=$aid, '
                                'photoId=${episode.photoId}, num=$num, '
                                'downloaded=$downloaded, '
                                'forceDecode=$needDecodeAnyway');
                            // 【诊断】同步写 scrambleId/aid/num 到 EXE 目录的诊断文件，
                            // 绕过 logger 库（logger 库在 release Windows 下未输出文件）。
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
                        // 单张图片下载失败，继续下一张
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

                // 章节内图片全部尝试下载后，记录该章节 photoId
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
                // 计算本子下载根目录
                final albumDir = '$downloadDir${Platform.pathSeparator}$safeAlbumTitle';
                // 真实下载封面到 albumDir/cover.jpg
                final localCoverPath =
                    await _downloadAlbumCover(
                        albumId,
                        '$albumDir${Platform.pathSeparator}cover.jpg',
                        fallbackFirstImage: lastSaveDir.isNotEmpty
                            ? '$lastSaveDir${Platform.pathSeparator}00001.jpg'
                            : '',
                    );
                // 本子下载根目录：downloadDir/safeAlbumTitle
                final localPath = albumDir;
                _emitStatusWithPayload(
                    taskId, 'completed', '下载完成', 1.0, downloadedPhotoIds,
                    author: albumDetail.author,
                    pageCount: albumDetail.pageCount,
                    episodeCount: albumDetail.episodeCount,
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

    /// 下载单个章节
    Future<void> downloadPhoto(String taskId, String photoId) async
    {
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        _taskStats[taskId] = _DownloadStats();

        try
        {
            await _taskDao.updateTaskStatus(taskId, 'running', '正在获取章节详情', 0.0);
            _emitStatus(taskId, 'running', '正在获取章节详情', 0.0);

            // 获取章节详情
            final photoDetail = await _client.getPhotoDetail(photoId);
            final scrambleId = await _client.getScrambleId(photoId);

            if (cancelToken.isCancelled) return;

            final totalImages = photoDetail.pageArr.length;
            await _taskDao.updateTaskProgress(taskId, 0, totalImages, 0.0);
            _emitProgress(taskId, 0, totalImages, 0.0, 'running', '正在下载');

            // 确保下载目录有效
            final downloadDir = _downloadDir.isEmpty
                ? await PathHelper.getDownloadDir()
                : _downloadDir;
            final saveDir = '$downloadDir${Platform.pathSeparator}$photoId';
            await Directory(saveDir).create(recursive: true);

            // 下载所有图片
            var completedImages = 0;

            for (var i = 0; i < photoDetail.pageArr.length; i++)
            {
                if (cancelToken.isCancelled) break;

                final filename = photoDetail.pageArr[i];
                final savePath = '$saveDir/${(i + 1).toString().padLeft(5, '0')}.jpg';

                try
                {
                    // 流式下载：已存在跳过，否则按需 Range 续传
                    final downloaded = await _client.downloadImageToFile(
                        photoId,
                        filename,
                        savePath,
                        cancelToken: cancelToken,
                    );

                    // 同 downloadAlbum 逻辑：旧 build 留下的未解密 WEBP 必须补做解密
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
                        // aid 必须是 photoId（章节ID），与 Python 参考实现的
                        // parse_to_jm_id(url) 一致（从 URL /media/photos/{photoId}/{filename} 提取）
                        //
                        // 注意：即使 scrambleId == 0（getScrambleId fallback）也要
                        // 跑 _decodeAndSave——_dio.download 把 webp 直接存到 .jpg
                        // 文件里，内容是 webp 但扩展名 jpg，必须转 jpg 才正常。
                        final aid = int.tryParse(photoId) ?? 0;
                        final num = JmImage.getSegmentationNum(
                            scrambleId, aid, filename,
                        );
                        _logger.i('[解密] $filename: '
                            'scrambleId=$scrambleId, aid=$aid, '
                            'photoId=$photoId, num=$num, '
                            'downloaded=$downloaded, '
                            'forceDecode=$needDecodeAnyway');
                        // 无论 num 是 0 还是 >0，都跑 _decodeAndSave：
                        // - num > 0：需要做行重排解密
                        // - num == 0：只做 webp→jpg 转码（platformDecode + encodeJpg）
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
                // 单章任务封面：使用首张已下载图（同时复制为 cover.jpg，便于统一访问）
                final firstImage = '$saveDir${Platform.pathSeparator}00001.jpg';
                final coverPath = await _ensurePhotoCover(saveDir, firstImage);
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

    /// 下载本子封面并保存为 cover.jpg
    /// 1) 优先尝试多个图片域名（与 image 域保持一致）
    /// 2) 失败时回退到 fallbackFirstImage（如本子第一张已下载图）
    /// 3) 最终返回真实可用的封面文件路径；全失败时返回空串
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
            // 创建目录失败时仍然继续尝试拷贝备用图
        }

        // 尝试从多个图片域名下载封面
        for (final size in const ['_3x4', '_2x3', ''])
        {
            final url = _client.getAlbumCoverUrl(albumId, size: size);
            if (await _fetchBytesToFile(url, savePath)) return savePath;
        }

        // 全部域失败 → 回退到本子第一张已下载图
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
                    // 复制失败时回退到返回源路径
                    return fallbackFirstImage;
                }
            }
        }
        return '';
    }

    /// 从 URL 拉取字节并写入文件
    /// 任何异常均视为失败，返回 false
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
            // ignore
        }
        return false;
    }

    /// 确保 photo 任务有 cover.jpg
    /// 1) cover.jpg 已存在 → 直接返回
    /// 2) 源图存在 → 复制为 cover.jpg 并返回
    /// 3) 全失败 → 回退到返回源图路径（让 UI 仍能显示）
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

    /// 读取已下载的加密图片，解密后覆盖保存
    /// 使用 JmImage.decode async API（内部含平台解码 + compute JPEG 编码）
    /// [savePath] 已下载的加密图路径
    /// [scrambleId] 章节 scramble_id
    /// [aid] 本子 ID
    /// [filename] 图片文件名
    Future<void> _decodeAndSave(
        String savePath,
        int scrambleId,
        int aid,
        String filename,
    ) async
    {
        try
        {
            // 解密前先清掉旧的 .ok 标记——失败回退到加密图时不能让标记残留
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
                // 忽略标记清理失败
            }

            final bytes = await File(savePath).readAsBytes();
            _logger.d('[解密] 开始: $filename, bytes=${bytes.length}');
            // 不再用 compute() 包裹整个 decode：
            // - image 包的 webp 解码器对部分文件抛 RangeError
            // - ui.instantiateImageCodec 必须在主线程
            // 现由 JmImage.decode 内部拆分为"主线程解码 + compute 编码"
            final decoded = await JmImage.decode(
                Uint8List.fromList(bytes),
                scrambleId,
                aid,
                filename,
            );
            await File(savePath).writeAsBytes(decoded);
            // 写 .ok 标记：isUndecodedWebp 靠它判断文件是否已解密成功
            // 写空内容即可，标记存在性就是全部信息
            await File(okPath).writeAsString('');
            _logger.d('[解密] 成功: $filename, before=${bytes.length}, after=${decoded.length}');
        }
        catch (e, st)
        {
            // 解密失败保留加密原图 - 显式记录错误方便排查
            _logger.w('[解密] 失败: $filename, 错误: $e');
            developer.log(
                'JmImage decode failed for $filename',
                name: 'DownloadService',
                error: e,
                stackTrace: st,
            );
        }
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
    void _emitProgress(
        String taskId,
        int current,
        int total,
        double progress,
        String status,
        String message,
    )
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: current,
            total: total,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
        ));
    }

    /// 发送状态变更事件（用于完成/失败/取消等状态）
    void _emitStatus(
        String taskId,
        String status,
        String message,
        double progress,
    )
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: 0,
            total: 0,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
        ));
    }

    /// 发送带附加负载的状态事件（用于完成时回传 photoId 列表与 album 元信息）
    void _emitStatusWithPayload(
        String taskId,
        String status,
        String message,
        double progress,
        List<String> downloadedPhotoIds, {
        String author = '',
        int pageCount = 0,
        int episodeCount = 0,
        String localCoverPath = '',
        String localPath = '',
    })
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: 0,
            total: 0,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
            downloadedPhotoIds: downloadedPhotoIds,
            author: author,
            pageCount: pageCount,
            episodeCount: episodeCount,
            localCoverPath: localCoverPath,
            localPath: localPath,
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
