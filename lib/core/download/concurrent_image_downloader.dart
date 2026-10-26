import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../common/app_logger.dart';
import '../jm/jm_client.dart';
import '../jm/jm_image.dart';
import '../../utils/file_helper.dart';

/// 并发信号量
///
/// 用于限制同时进行的异步操作数量。
/// 用法：调用方在执行前 [acquire]，执行完毕后 [release]（建议在 `finally` 中）。
class DownloadSemaphore
{
    /// 最大许可数
    final int maxPermits;

    /// 当前可用许可
    int _permits;

    /// 等待获取许可的队列（FIFO）
    final List<Completer<void>> _waiters = <Completer<void>>[];

    DownloadSemaphore(this.maxPermits) : _permits = maxPermits;

    /// 阻塞直到获得一个许可
    Future<void> acquire()
    {
        if (_permits > 0)
        {
            _permits--;
            return Future<void>.value();
        }
        final completer = Completer<void>();
        _waiters.add(completer);
        return completer.future;
    }

    /// 释放一个许可
    ///
    /// 若有等待者，立即唤醒队首；否则将许可归还到池中。
    void release()
    {
        if (_waiters.isNotEmpty)
        {
            _waiters.removeAt(0).complete();
        }
        else
        {
            _permits++;
        }
    }
}

/// 图片域名轮询分配器
///
/// 多线程并发下载时，每条线程从 [JmClient.imageDomainList] 中
/// 轮询取得一个不同的起始下标，传给 [JmClient.downloadImageToFile] 的
/// `startDomainIndex` 参数，使各线程优先使用不同域名，避免扎堆。
class DomainRotator
{
    /// 当前域名列表大小（在创建时确定，运行中不会自动跟随）
    final int domainCount;

    /// 原子递增计数器
    int _counter = 0;

    DomainRotator(this.domainCount);

    /// 取出下一个起始域名下标（线程安全，按自增顺序轮询）
    int nextIndex()
    {
        if (domainCount <= 0) return 0;
        final i = _counter;
        _counter = (_counter + 1) % domainCount;
        return i;
    }
}

/// 单张图片下载与解密结果
class ImageDownloadResult
{
    /// 文件名
    final String filename;

    /// 页码下标（0-based）
    final int pageIndex;

    /// 是否成功（下载且解密均成功，或本地已存在有效文件）
    final bool success;

    /// 实际写入文件的字节数（成功时有效）
    final int bytes;

    const ImageDownloadResult({
        required this.filename,
        required this.pageIndex,
        required this.success,
        this.bytes = 0,
    });
}

/// 并发下载单张图片：HTTP 下载 + 解密 + 写盘 + 写 `.ok` 标记
///
/// 本函数封装了"一张图从网络到本地完成"的全流程，被 [DownloadService] 整本下载、
/// 单章下载以及 [SmartDownloadService] 在线预下载共用：
/// - 优先使用本地已存在的解密后文件（带 `.ok` 标记）→ 跳过
/// - 通过 [JmClient.downloadImageToFile] 下载原图
/// - 如返回 false 但本地有未解密 WebP，也尝试解密
/// - 成功后写 `.ok` 标记，便于下次识别
///
/// 调用前需先 [DownloadSemaphore.acquire]，调用后通过 `finally` [DownloadSemaphore.release]，
/// 本函数不再管理信号量。
///
/// [rotator] 若非空，每条任务会从中取一个起始域名下标传给 JmClient，让不同线程
/// 从不同域名开始尝试（具体实现见 [JmClient.downloadImageToFile] 的 startDomainIndex）。
Future<ImageDownloadResult> downloadOneImageWithDecode({
    required JmClient client,
    required CancelToken cancelToken,
    required String photoId,
    required String filename,
    required int pageIndex,
    required String saveDir,
    required int scrambleId,
    required int aid,
    DomainRotator? rotator,
}) async
{
    final savePath = '$saveDir/${(pageIndex + 1).toString().padLeft(5, '0')}.jpg';
    final okPath = '$savePath.ok';

    // 异步检查：已存在且有效则跳过
    final saveExists = await FileExistenceCache.fileExists(savePath);
    final okExists = saveExists && await FileExistenceCache.fileExists(okPath);
    if (saveExists && okExists)
    {
        try
        {
            final bytes = await File(savePath).length();
            return ImageDownloadResult(
                filename: filename,
                pageIndex: pageIndex,
                success: true,
                bytes: bytes,
            );
        }
        catch (_)
        {
            // 文件可能被删除，继续下载
        }
    }

    try
    {
        if (cancelToken.isCancelled)
        {
            return ImageDownloadResult(
                filename: filename,
                pageIndex: pageIndex,
                success: false,
            );
        }

        final downloaded = await client.downloadImageToFile(
            photoId,
            filename,
            savePath,
            cancelToken: cancelToken,
            startDomainIndex: rotator?.nextIndex(),
        );

        final f = File(savePath);
        final fExists = await f.exists();
        // 下载失败且本地没有任何文件：明确返回失败，避免上层把该页
        // 误记为"已完成"（会让进度虚高、并在续传时与真实文件不一致）
        if (!fExists)
        {
            return ImageDownloadResult(
                filename: filename,
                pageIndex: pageIndex,
                success: false,
            );
        }

        final needDecodeAnyway = !downloaded && JmImage.isUndecodedWebp(savePath);
        var decodeOk = true;
        if (downloaded || needDecodeAnyway)
        {
            decodeOk = await _decodeAndSave(
                savePath,
                scrambleId,
                aid,
                filename,
            );
        }

        final bytes = await f.length();
        // 以 `.ok` 标记为准：只有解密成功并落标记才算这一页真正完成
        final okExists = await FileExistenceCache.fileExists(okPath);
        return ImageDownloadResult(
            filename: filename,
            pageIndex: pageIndex,
            success: decodeOk && okExists && bytes > 0,
            bytes: bytes,
        );
    }
    catch (e, st)
    {
        _logger.w('[下载] $photoId/$filename 失败: $e');
        developer.log(
            'downloadOneImageWithDecode failed: $photoId/$filename',
            name: 'ConcurrentImageDownloader',
            error: e,
            stackTrace: st,
        );
        return ImageDownloadResult(
            filename: filename,
            pageIndex: pageIndex,
            success: false,
        );
    }
}

/// 解密并覆盖保存到原路径，成功后写 `.ok` 标记
///
/// 与 [SmartDownloadService] / [DownloadService] 中的旧实现行为完全一致：
/// - 先删除已有的 `.ok` 标记（如果存在）
/// - 读取原图字节
/// - 调用 [JmImage.decode] 解密
/// - 写回原路径
/// - 写空 `.ok` 标记
///
/// 返回是否成功写入 `.ok`；失败时不抛异常（避免影响下载流程），仅记录日志。
Future<bool> _decodeAndSave(
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
            if (await File(okPath).exists())
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
        // 写入后使缓存失效，确保后续检查能感知新文件
        FileExistenceCache.invalidate(savePath);
        FileExistenceCache.invalidate(okPath);
        _logger.d('[解密] 成功: $filename, '
            'before=${bytes.length}, after=${decoded.length}');
        return true;
    }
    catch (e, st)
    {
        _logger.w('[解密] 失败: $filename, 错误: $e');
        developer.log(
            'JmImage decode failed for $filename',
            name: 'ConcurrentImageDownloader',
            error: e,
            stackTrace: st,
        );
        return false;
    }
}

/// 模块级单例日志器
final AppLogger _logger = AppLogger();
