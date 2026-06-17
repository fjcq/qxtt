// 真实 jmcomic 加密图 num=14 → Dart JmImage.decodeImagePixels（不经过 JPEG 重新编码），
// 直接输出原始 RGBA 为 PNG，与 Python 端 expected_decoded.png 像素级比对。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    test('真实 jmcomic 加密图 num=14 → decodeImagePixels 纯算法 vs Python',
        () async
    {
        final enc = File(r'e:\MyServer\JMComic\verify_assets\real_scrambled.jpg');
        final expected = File(r'e:\MyServer\JMComic\verify_assets\expected_decoded.png');
        final out = File(r'e:\MyServer\JMComic\verify_assets\dart_decoded_raw.png');
        expect(enc.existsSync(), isTrue);
        expect(expected.existsSync(), isTrue);

        // 1) 用 platform codec 解码 WebP → RGBA
        final encBytes = enc.readAsBytesSync();
        final codec = await ui.instantiateImageCodec(
            Uint8List.fromList(encBytes),
        );
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;
        final w = uiImage.width;
        final h = uiImage.height;
        final byteData = await uiImage.toByteData(
            format: ui.ImageByteFormat.rawRgba,
        );
        final rgba = Uint8List.fromList(
            byteData!.buffer.asUint8List(),
        );
        print('Dart codec 解码: ${w}x$h, RGBA=${rgba.length} bytes');
        uiImage.dispose();
        codec.dispose();

        // 2) 直接调用 decodeImagePixels（num=14，无 JPEG 编码）
        const num = 14;
        JmImage.decodeImagePixels(rgba, w, h, num);

        // 3) 编码为 PNG（无损）
        final decoded = img.Image.fromBytes(
            width: w, height: h,
            bytes: rgba.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
        );
        out.writeAsBytesSync(img.encodePng(decoded));
        print('已写出 dart_decoded_raw.png');

        // 4) 与 Python 端 expected_decoded.png 像素级比对
        final expBytes = expected.readAsBytesSync();
        final expImg = img.decodePng(expBytes)!;
        final e4 = expImg.numChannels == 4
            ? expImg
            : expImg.convert(numChannels: 4, alpha: 255);
        final eLen = w * h * 4;
        final eData = e4.data as img.ImageDataUint8;
        final eRgba = Uint8List(eLen);
        final eView = Uint8List.view(
            eData.data.buffer, eData.data.offsetInBytes, eLen,
        );
        for (var i = 0; i < eLen; i++) eRgba[i] = eView[i];

        var diff = 0;
        var maxDelta = 0;
        for (var i = 0; i < eLen; i++)
        {
            if (rgba[i] != eRgba[i])
            {
                diff++;
                final d = (rgba[i] - eRgba[i]).abs();
                if (d > maxDelta) maxDelta = d;
            }
        }
        print('差异字节: $diff / $eLen (max delta=$maxDelta)');

        if (diff == 0)
        {
            print('[OK] Dart decodeImagePixels 与 Python 完全一致');
        }
        else
        {
            print('[FAIL] 算法实现有 $diff 字节差异');
        }
    });
}
