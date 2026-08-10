import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// 解密参数（跨 isolate 传输）
/// 保留类型以便旧调用方编译通过；新流程由 [JmImage.decode] 内部处理
@Deprecated('JmImage.decode 改为 async 后不再需要外部传参')
class DecodeArgs
{
    final Uint8List imageBytes;
    final int scrambleId;
    final int aid;
    final String filename;

    const DecodeArgs({
        required this.imageBytes,
        required this.scrambleId,
        required this.aid,
        required this.filename,
    });
}

/// Isolate 入口：调用 JmImage.decode
/// 旧版同步入口（仍兼容 jm_image_loader 与 download_service 的旧调用）
/// 注意：image 包的 webp 解码器对部分文件会抛 RangeError。
/// 新版 JmImage.decode 改为 async 并改用平台原生解码器 [ui.instantiateImageCodec]，
/// 兼容性与稳定性远好于 image 包的 libwebp binding。
@Deprecated('请改用 JmImage.decode async API')
Uint8List decodeImageInIsolate(DecodeArgs args)
{
    // 此入口仅保留为旧同步调用方兜底；遇 RangeError 时返回空 bytes（调用方需处理）
    try
    {
        return JmImage.decodeSyncLegacy(
            args.imageBytes, args.scrambleId, args.aid, args.filename,
        );
    }
    catch (e)
    {
        return Uint8List(0);
    }
}

/// 禁漫图片分割解密工具
class JmImage
{
    /// 计算图片分割数
    ///
    /// 重要：filename 入参会自动**去后缀**（'00001.webp' → '00001'），与 Python 参考
    /// 实现 `JmImageTool.get_num_by_detail` / `get_num_by_url` 一致——后者均通过
    /// `of_file_name(url, True)` / `JmImageDetail.img_file_name` 拿到去后缀的 filename。
    /// 例如 1440552 + '00001' 算出 num=14；带后缀的 '00001.webp' 会算成 num=2（错）。
    /// 规则（与 Python jmcomic 库 `JmImageTool.get_num` 完全一致）：
    /// - aid < scramble_id → 0 (无需解密)
    /// - aid < 268850 → 10
    /// - aid < 421926 → x=10, 否则 x=8
    ///   num = md5("{aid}{filenameNoExt}") 最后一个字符的 codeUnit % x * 2 + 2
    ///
    /// **关键验证（1440552 章节）**：
    /// `python_src/00001.webp`（JM 服务端返回的原始 webp，109129 字节）
    /// 用 Python 库跑 num=14 解密 → `py_lib_n14.jpg` 像素与 src.webp
    /// 直转 jpg 差异 98.6%（行重排效果）→ 这就是真图。
    /// 也就是说：`aid(1440552) > scramble_id(220980)` → 必须 num=14 解密
    /// 才能拿到真图。"scrambleId=220980 时 num=0" 是错的反向修复——
    /// 会让 1440552 章节永远显示错乱图。
    static int getSegmentationNum(int scrambleId, int aid, String filename)
    {
        if (aid < scrambleId)
        {
            return 0;
        }
        if (aid < 268850)
        {
            return 10;
        }
        // 与 Python 库对齐：filename 去掉后缀后再参与 md5
        // 例如 '00001.webp' → '00001'，'00001.jpg' → '00001'
        final nameNoSuffix = filename.contains('.')
            ? filename.substring(0, filename.lastIndexOf('.'))
            : filename;
        final x = aid < 421926 ? 10 : 8;
        final hash = md5.convert(utf8.encode('$aid$nameNoSuffix')).toString();
        final lastChar = hash.codeUnitAt(hash.length - 1);
        final num = lastChar % x;
        return num * 2 + 2;
    }

    /// 图片分割解密（像素级操作）
    /// 按 num 段分割并重排像素（in-place 修改 rgbaBytes）
    /// [rgbaBytes] 长度必须等于 width*height*4
    /// [width] 像素宽
    /// [height] 像素高
    /// [num] 分割段数
    static void decodeImagePixels(
        Uint8List rgbaBytes,
        int width,
        int height,
        int num,
    )
    {
        if (num == 0 || rgbaBytes.isEmpty) return;

        // 关键：Dart native VM 上 Uint8List/buffer 视图（asUint8List 不带 length）
        // 会因内存对齐而带 padding 字节，访问 view 末尾时会差几字节越界。
        // 解决方案：完全不依赖 view，全部用独立 Uint8List/Uint32List。

        // 1) 把 rgbaBytes 按 4 字节/像素 读出为 uint32 数组
        final pixelCount = width * height;
        final srcPixels = Uint32List(pixelCount);
        for (var i = 0; i < pixelCount; i++)
        {
            final off = i * 4;
            // 大端序：RGBA -> R<<24 | G<<16 | B<<8 | A
            srcPixels[i] = (rgbaBytes[off] << 24) |
                (rgbaBytes[off + 1] << 16) |
                (rgbaBytes[off + 2] << 8) |
                rgbaBytes[off + 3];
        }

        // 2) 行重排
        final temp = Uint32List(pixelCount);
        final over = height % num;

        for (var i = 0; i < num; i++)
        {
            final moveVal = height ~/ num;
            final ySrc = height - moveVal * (i + 1) - over;
            final yDst = moveVal * i;

            int actualYSrc, actualYDst, actualH;
            if (i == 0)
            {
                actualYSrc = ySrc;
                actualYDst = yDst;
                actualH = moveVal + over;
            }
            else
            {
                actualYSrc = ySrc;
                actualYDst = yDst + over;
                actualH = moveVal;
            }

            for (var row = 0; row < actualH; row++)
            {
                final srcOff = (actualYSrc + row) * width;
                final dstOff = (actualYDst + row) * width;
                for (var col = 0; col < width; col++)
                {
                    temp[dstOff + col] = srcPixels[srcOff + col];
                }
            }
        }

        // 3) 写回 rgbaBytes
        for (var i = 0; i < pixelCount; i++)
        {
            final v = temp[i];
            final off = i * 4;
            rgbaBytes[off]     = (v >> 24) & 0xFF;
            rgbaBytes[off + 1] = (v >> 16) & 0xFF;
            rgbaBytes[off + 2] = (v >> 8) & 0xFF;
            rgbaBytes[off + 3] = v & 0xFF;
        }
    }

    // 私有构造函数，防止实例化
    JmImage._();

    /// 截取字节数组前 N 字节转 hex 字符串（调试用）
    static String _hexPreview(Uint8List bytes, int n)
    {
        final len = bytes.length < n ? bytes.length : n;
        final sb = StringBuffer();
        for (var i = 0; i < len; i++)
        {
            sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
            if (i < len - 1) sb.write(' ');
        }
        return sb.toString();
    }

    /// 使用 Flutter 平台原生解码器解码图片（必须主线程）
    /// - Windows: WIC
    /// - macOS/iOS: ImageIO
    /// - Linux: Skia (经 Flutter engine)
    /// 相比 image 包的 libwebp binding 兼容性显著更好（不会抛 RangeError）
    /// 失败时抛出包含文件名/字节数/错误类型的异常
    static Future<PlatformDecodeResult> platformDecode(
        Uint8List imageBytes,
        String filename,
    ) async
    {
        if (imageBytes.isEmpty)
        {
            throw Exception('图片字节为空: $filename');
        }

        ui.Codec codec;
        try
        {
            codec = await ui.instantiateImageCodec(imageBytes);
        }
        catch (e)
        {
            throw Exception(
                '图片解码失败(instantiateImageCodec): $filename, '
                'bytes=${imageBytes.length}, '
                'head=${_hexPreview(imageBytes, 16)}, '
                'err=${e.runtimeType}: $e',
            );
        }

        ui.FrameInfo frame;
        try
        {
            frame = await codec.getNextFrame();
        }
        catch (e)
        {
            codec.dispose();
            throw Exception(
                '图片帧获取失败: $filename, '
                'bytes=${imageBytes.length}, '
                'err=${e.runtimeType}: $e',
            );
        }

        final uiImage = frame.image;
        final width = uiImage.width;
        final height = uiImage.height;

        final ByteData? byteData = await uiImage.toByteData(
            format: ui.ImageByteFormat.rawRgba,
        );
        // 释放 native 资源
        uiImage.dispose();
        codec.dispose();

        if (byteData == null)
        {
            throw Exception(
                '图片字节转换失败(toByteData): $filename, '
                'bytes=${imageBytes.length}, ${width}x$height',
            );
        }

        // 关键：byteData 引用 native memory，必须复制到独立 buffer
        // 否则后续操作（unscramble / encodeJpg）会读到错乱的内存
        final rgba = Uint8List.fromList(
            byteData.buffer.asUint8List(0, byteData.lengthInBytes),
        );

        return PlatformDecodeResult(rgba, width, height);
    }

    /// 解密单张禁漫图片（异步，推荐使用）
    /// 输入：加密的原始图片字节
    /// 输出：解密后的 JPEG 字节
    ///
    /// 流程：
    ///   1) 主线程：用 [ui.instantiateImageCodec] 平台原生解码（解决 image 包 RangeError）
    ///   2) 主线程：判断是否需要 unscramble，in-place 修改 RGBA
    ///   3) compute isolate：[img.encodeJpg] 编码为 JPEG（不阻塞 UI）
    ///
    /// 注意：曾尝试将整个解码流程（含 [ui.instantiateImageCodec]）放入 [Isolate.run]
    /// 以避免大图解码时 UI 卡顿。但在 Windows 上发现后台 isolate 调用
    /// [ui.instantiateImageCodec] 解出的 RGBA 像素与主 isolate 不一致，
    /// 导致下载图片解密后画面错乱（头身错位）。因此回退为「主线程解码 + compute 编码」。
    ///
    /// [scrambleId] 章节 scramble_id
    /// [aid] 本子 ID（整数）
    /// [filename] 图片文件名
    static Future<Uint8List> decode(
        Uint8List imageBytes,
        int scrambleId,
        int aid,
        String filename,
    ) async
    {
        // 1. 平台解码（主线程）
        final decoded = await platformDecode(imageBytes, filename);

        // 2. 判断是否需要分割解密
        final num = getSegmentationNum(scrambleId, aid, filename);
        if (num > 0)
        {
            // in-place 修改 decoded.rgba
            decodeImagePixels(decoded.rgba, decoded.width, decoded.height, num);
        }

        // 3. JPEG 编码（compute isolate，不阻塞 UI）
        return await compute(
            _encodeRgbaAsJpegInIsolate,
            _EncodeJpegArgs(decoded.rgba, decoded.width, decoded.height),
        );
    }

    /// 旧版同步解码（仅供 [decodeImageInIsolate] 兼容用）
    /// 不推荐：新代码应使用 [decode]
    @Deprecated('请改用 JmImage.decode async API')
    static Uint8List decodeSyncLegacy(
        Uint8List imageBytes,
        int scrambleId,
        int aid,
        String filename,
    )
    {
        // 这里仍用 image 包的 decoder，因为同步实现无法使用 ui.instantiateImageCodec
        // 调用方应捕获 RangeError 并降级到下载流程
        if (imageBytes.isEmpty)
        {
            throw Exception('图片字节为空: $filename');
        }

        final source = img.decodeImage(imageBytes);
        if (source == null)
        {
            throw Exception(
                '图片解码失败: $filename, bytes=${imageBytes.length}, '
                'head=${_hexPreview(imageBytes, 16)}',
            );
        }
        final width = source.width;
        final height = source.height;

        final num = getSegmentationNum(scrambleId, aid, filename);
        if (num == 0)
        {
            return Uint8List.fromList(img.encodeJpg(source, quality: 90));
        }

        final src4 = source.numChannels == 4
            ? source
            : source.convert(numChannels: 4, alpha: 255);

        final pixelCount = width * height;
        final rgbaByteLen = pixelCount * 4;
        final rgba = Uint8List(rgbaByteLen);
        final src4Data = src4.data as img.ImageDataUint8;
        final src4Bytes = Uint8List.view(
            src4Data.data.buffer,
            src4Data.data.offsetInBytes,
            rgbaByteLen,
        );
        for (var i = 0; i < rgbaByteLen; i++)
        {
            rgba[i] = src4Bytes[i];
        }

        decodeImagePixels(rgba, width, height, num);

        final decoded = img.Image.fromBytes(
            width: width,
            height: height,
            bytes: rgba.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
        );
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
    }

    /// 探测本地是否已下载该图片（用于在线阅读器走本地优先策略）
    /// 命中条件: ${downloadDir}/{albumTitle}/{episodeIndex}/00001.jpg 这种命名约定
    /// 该函数依赖调用方传入查找路径
    static bool isLocalFileExists(String filePath)
    {
        return File(filePath).existsSync();
    }

    /// 探测本地图片文件是否仍需解密
    ///
    /// 判定规则（任一满足即返回 true）：
    /// 1. 文件头是 'RIFF....WEBP'（原下载的加密 WEBP 没解过）
    /// 2. 同目录下没有 `<文件名>.ok` 标记文件（之前没跑过 _decodeAndSave 或跑失败/被回退）
    ///
    /// **为什么用 .ok 标记而不只靠文件头**：
    /// 之前某些错误路径下，"加密 WEBP" 可能被错误地 encodeJpg 后保存为 .jpg 后缀，
    /// 头变成 FF D8 FF，靠文件头识别不出来。
    /// .ok 标记由 _decodeAndSave 显式写入，是"已成功解密"的唯一可信信号。
    /// 删除 _decodeAndSave 解密产物时务必同时删 .ok 标记，否则下次会误判为已解密。
    /// - 文件不存在时返回 false
    static bool isUndecodedWebp(String filePath)
    {
        try
        {
            final f = File(filePath);
            if (!f.existsSync())
            {
                return false;
            }

            // 规则 1: 头是 RIFF....WEBP 一定是未解密的原图
            final raf = f.openSync(mode: FileMode.read);
            try
            {
                final bytes = raf.readSync(12);
                if (bytes.length >= 12 &&
                    bytes[0] == 0x52 && bytes[1] == 0x49 &&
                    bytes[2] == 0x46 && bytes[3] == 0x46 &&
                    bytes[8] == 0x57 && bytes[9] == 0x45 &&
                    bytes[10] == 0x42 && bytes[11] == 0x50)
                {
                    return true;
                }
            }
            finally
            {
                raf.closeSync();
            }

            // 规则 2: 缺少 .ok 标记视为未解密
            // 防止"加密图被错误保存为 jpg"逃过检测
            final okPath = '$filePath.ok';
            if (!File(okPath).existsSync())
            {
                return true;
            }

            return false;
        }
        catch (_)
        {
            return false;
        }
    }
}

/// compute 跨 isolate 传输：RGBA → JPEG 编码参数
class _EncodeJpegArgs
{
    final Uint8List rgba;
    final int width;
    final int height;

    const _EncodeJpegArgs(this.rgba, this.width, this.height);
}

/// compute isolate 入口：把 RGBA 像素编码为 JPEG
/// 此函数必须保持 sync（compute() 的 callback 是 sync）
Uint8List _encodeRgbaAsJpegInIsolate(_EncodeJpegArgs args)
{
    final img.Image image = img.Image.fromBytes(
        width: args.width,
        height: args.height,
        bytes: args.rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// 平台原生解码结果（RGBA 像素 + 尺寸）
/// RGBA 字节长度 = width * height * 4
class PlatformDecodeResult
{
    final Uint8List rgba;
    final int width;
    final int height;
    const PlatformDecodeResult(this.rgba, this.width, this.height);
}
