import 'dart:async';
import 'dart:typed_data';

import 'jm_client.dart';
import 'jm_image.dart';

/// 图片加载进度
class ImageLoadProgress
{
    /// 0.0 ~ 1.0
    final double progress;

    /// 阶段描述
    final String stage;

    const ImageLoadProgress(this.progress, this.stage);
}

/// 单张图片加载结果
class ImageLoadResult
{
    /// 解密后的 JPEG 字节
    final Uint8List bytes;

    /// 原始宽度
    final int width;

    /// 原始高度
    final int height;

    /// 命中解密结果缓存（key=photoId_filename）
    final bool fromDecodedCache;

    const ImageLoadResult({
        required this.bytes,
        required this.width,
        required this.height,
        this.fromDecodedCache = false,
    });
}

/// 禁漫图片在线加载器
/// 负责: 下载原图 → 解码 → 分割解密 → 重新编码为 JPEG
class JmImageLoader
{
    final JmClient _client;

    JmImageLoader(this._client);

    /// 加载并解密单张图片
    /// [photoId] 章节 ID
    /// [filename] 图片文件名
    /// [scrambleId] 章节 scramble_id
    /// [aid] 本子 ID（整数）
    /// [onProgress] 进度回调
    /// 返回解密后的 JPEG 字节
    ///
    /// 注意：本方法已不再用 compute() 包裹整个解码流程。
    /// 原因：image 包的 webp 解码器对部分文件抛 RangeError（buffer 长度差 1 字节）。
    /// 现改用 [JmImage.decode] 的 async API，内部使用平台原生解码器
    /// （Windows WIC / macOS ImageIO），兼容性远好于 image 包。
    /// JPEG 编码仍走 compute isolate（不阻塞 UI）。
    Future<ImageLoadResult> loadAndDecode({
        required String photoId,
        required String filename,
        required int scrambleId,
        required int aid,
        void Function(ImageLoadProgress)? onProgress,
    }) async
    {
        // 0. 先查"解密结果"磁盘缓存
        final cachedBytes = await JmImageCacheManager.getDecoded(photoId, filename);
        if (cachedBytes != null)
        {
            onProgress?.call(const ImageLoadProgress(1.0, '已缓存'));
            return ImageLoadResult(
                bytes: cachedBytes,
                width: 0,
                height: 0,
                fromDecodedCache: true,
            );
        }

        // 1. 下载原图
        onProgress?.call(const ImageLoadProgress(0.1, '下载中'));
        final imageBytes = await _client.downloadImage(photoId, filename);

        // 2. 解密（平台解码 + unscramble + JPEG 编码）
        // 不再 wrap compute()，因为 ui.instantiateImageCodec 必须在主线程运行
        onProgress?.call(const ImageLoadProgress(0.5, '解码中'));
        final decodedBytes = await JmImage.decode(
            Uint8List.fromList(imageBytes),
            scrambleId,
            aid,
            filename,
        );

        onProgress?.call(const ImageLoadProgress(0.9, '编码中'));

        // 3. 写入"解密结果"磁盘缓存
        await JmImageCacheManager.putDecoded(
            photoId, filename, decodedBytes,
        );

        onProgress?.call(const ImageLoadProgress(1.0, '完成'));

        return ImageLoadResult(
            bytes: decodedBytes,
            width: 0,
            height: 0,
        );
    }
}
