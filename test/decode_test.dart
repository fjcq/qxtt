// 测试 JmImage.decode 在 jpg 上的行为
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main(List<String> args)
{
    if (args.isEmpty) {
        print('Usage: dart test_decode.dart <image.jpg> [scramble_id] [aid]');
        return;
    }
    final file = File(args[0]);
    if (!file.existsSync()) {
        print('File not found: ${args[0]}');
        return;
    }

    final bytes = file.readAsBytesSync();
    final scrambleId = args.length > 1 ? int.parse(args[1]) : 10;
    final aid = args.length > 2 ? int.parse(args[2]) : 0;

    final source = img.decodeImage(Uint8List.fromList(bytes));
    if (source == null) {
        print('decodeImage failed');
        return;
    }
    print('source: ${source.width}x${source.height}, numChannels=${source.numChannels}');

    // 1) 直接编码（不加密）
    try {
        final jpg1 = img.encodeJpg(source, quality: 90);
        print('encodeJpg (no convert): OK, ${jpg1.length} bytes');
    } catch (e) {
        print('encodeJpg (no convert) FAILED: $e');
    }

    // 2) 转换 4 channels
    try {
        final src4 = source.numChannels == 4 ? source : source.convert(numChannels: 4, alpha: 255);
        print('src4: ${src4.width}x${src4.height}, numChannels=${src4.numChannels}');
        print('src4.data.data.length = ${(src4.data as img.ImageDataUint8).data.length}');
        print('expected = ${src4.width * src4.height * 4}');
        final jpg2 = img.encodeJpg(src4, quality: 90);
        print('encodeJpg (after convert): OK, ${jpg2.length} bytes');
    } catch (e) {
        print('convert/encodeJpg FAILED: $e');
    }

    // 3) 用 getPixel 逐像素读，setPixelRgba 写
    try {
        final src4 = source.numChannels == 4 ? source : source.convert(numChannels: 4, alpha: 255);
        final w = src4.width;
        final h = src4.height;
        final expected = w * h * 4;
        final rgba = Uint8List(expected);
        for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
                final p = src4.getPixel(x, y);
                final off = (y * w + x) * 4;
                rgba[off]     = p.r.toInt();
                rgba[off + 1] = p.g.toInt();
                rgba[off + 2] = p.b.toInt();
                rgba[off + 3] = p.a.toInt();
            }
        }
        print('getPixel: OK, rgba.length = ${rgba.length}');

        final decoded = img.Image(width: w, height: h, numChannels: 4);
        final dstData = decoded.data as img.ImageDataUint8;
        print('decoded.data.data.length = ${dstData.data.length}');
        for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
                final off = (y * w + x) * 4;
                decoded.setPixelRgba(x, y, rgba[off], rgba[off + 1], rgba[off + 2], rgba[off + 3]);
            }
        }
        final jpg3 = img.encodeJpg(decoded, quality: 90);
        print('getPixel + setPixelRgba + encodeJpg: OK, ${jpg3.length} bytes');
    } catch (e) {
        print('getPixel path FAILED: $e');
    }
}
