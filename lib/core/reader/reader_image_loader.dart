import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../jm/jm_image.dart';
import '../jm/jm_image_cache_manager.dart';
import 'reader_download_engine.dart';

/// 阅读图片加载结果
class ReaderImageResult
{
    /// 解密后的 JPEG 字节
    final Uint8List bytes;

    /// 来源
    final ReaderImageSource source;

    const ReaderImageResult({
        required this.bytes,
        required this.source,
    });
}

/// 图片来源
enum ReaderImageSource
{
    /// 内存缓存
    memory,

    /// 临时解密缓存
    decodedCache,

    /// 网络下载
    network,
}

/// 阅读图片加载进度
class ReaderImageProgress
{
    /// 阶段描述
    final String stage;

    /// 0.0 ~ 1.0
    final double progress;

    const ReaderImageProgress(this.stage, this.progress);
}

/// 简单 LRU 内存缓存
class _ImageMemoryCache
{
    final int maxSize;
    final _map = <String, Uint8List>{};
    final _accessOrder = <String>[];

    _ImageMemoryCache({this.maxSize = 20});

    Uint8List? get(String key)
    {
        final bytes = _map[key];
        if (bytes == null) return null;
        _touch(key);
        return bytes;
    }

    void put(String key, Uint8List bytes)
    {
        if (_map.containsKey(key))
        {
            _map[key] = bytes;
            _touch(key);
            return;
        }

        if (_map.length >= maxSize && _accessOrder.isNotEmpty)
        {
            final oldest = _accessOrder.removeAt(0);
            _map.remove(oldest);
        }

        _map[key] = bytes;
        _accessOrder.add(key);
    }

    void clear()
    {
        _map.clear();
        _accessOrder.clear();
    }

    void _touch(String key)
    {
        _accessOrder.remove(key);
        _accessOrder.add(key);
    }
}

/// 统一阅读图片加载器
/// 用于在线阅读当前页/预加载页的快速加载
/// 加载优先级：内存缓存 → 临时解密缓存 → 网络下载
/// 本地文件（已下载）由 OnlineImageViewer 优先处理，不走此处
class ReaderImageLoader
{
    final ReaderDownloadEngine _engine;

    /// 内存缓存（跨章节共享，避免重复解码）
    static final _memoryCache = _ImageMemoryCache(maxSize: 30);

    ReaderImageLoader({
        required ReaderDownloadEngine engine,
    }) : _engine = engine;

    /// 清空内存缓存
    static void clearMemoryCache()
    {
        _memoryCache.clear();
    }

    /// 加载单张图片
    Future<ReaderImageResult> load({
        required String photoId,
        required String filename,
        required int scrambleId,
        required int aid,
        DownloadPriority priority = DownloadPriority.background,
        CancelToken? cancelToken,
        void Function(ReaderImageProgress)? onProgress,
    }) async
    {
        final key = '${photoId}_$filename';

        // 1. 内存缓存
        final mem = _memoryCache.get(key);
        if (mem != null)
        {
            onProgress?.call(const ReaderImageProgress('内存', 1.0));
            return ReaderImageResult(bytes: mem, source: ReaderImageSource.memory);
        }

        // 2. 临时解密缓存
        onProgress?.call(const ReaderImageProgress('缓存', 0.0));
        final decodedCache = await JmImageCacheManager.getDecoded(photoId, filename);
        if (decodedCache != null)
        {
            _memoryCache.put(key, decodedCache);
            onProgress?.call(const ReaderImageProgress('缓存', 1.0));
            return ReaderImageResult(
                bytes: decodedCache,
                source: ReaderImageSource.decodedCache,
            );
        }

        // 3. 网络下载
        onProgress?.call(const ReaderImageProgress('下载中', 0.1));
        final bytes = await _engine.enqueue(
            photoId: photoId,
            filename: filename,
            scrambleId: scrambleId,
            aid: aid,
            priority: priority,
            cancelToken: cancelToken,
            onProgress: (p)
            {
                onProgress?.call(ReaderImageProgress(p.stage, p.progress));
            },
        );

        _memoryCache.put(key, bytes);

        // 异步回写临时解密缓存
        unawaited(JmImageCacheManager.putDecoded(photoId, filename, bytes));

        return ReaderImageResult(bytes: bytes, source: ReaderImageSource.network);
    }

    /// 预加载单张图片（低优先级，不等待结果）
    void preload({
        required String photoId,
        required String filename,
        required int scrambleId,
        required int aid,
    })
    {
        unawaited(load(
            photoId: photoId,
            filename: filename,
            scrambleId: scrambleId,
            aid: aid,
            priority: DownloadPriority.preload,
        ));
    }

    /// 取消指定图片的下载
    void cancel(String photoId, String filename)
    {
        _engine.cancel(photoId, filename);
    }
}
