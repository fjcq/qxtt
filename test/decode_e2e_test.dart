// 端到端验证：用 Python 生成的 scrambled.png 在 Dart 端解密，
// 输出 decoded.png，与 original.png 像素级比对。
// 验证 JmImage.decodeImagePixels 算法与 Python 参考实现 100% 一致。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    test('Python generated scrambled.png → Dart decode → 比对 original.png',
        () async
    {
        final assetsDir = r'e:\MyServer\JMComic\verify_assets';
        final scrambled = File('$assetsDir\\scrambled.png');
        final original = File('$assetsDir\\original.png');
        final decoded = File('$assetsDir\\decoded.png');

        expect(scrambled.existsSync(), isTrue, reason: 'scrambled.png 不存在');
        expect(original.existsSync(), isTrue, reason: 'original.png 不存在');

        // 1) 读取 scrambled.png 的 RGBA 像素
        final scrambledBytes = scrambled.readAsBytesSync();
        final scrambledImg = img.decodePng(scrambledBytes)!;
        final width = scrambledImg.width;
        final height = scrambledImg.height;
        print('scrambled.png: ${width}x$height');

        // 强制 4 通道
        final src4 = scrambledImg.numChannels == 4
            ? scrambledImg
            : scrambledImg.convert(numChannels: 4, alpha: 255);
        final rgbaByteLen = width * height * 4;
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

        // 2) 调用 JmImage.decodeImagePixels（num 必须与生成时一致）
        // aid=500000, filename=00013, scramble_id=220000 → num=10
        const num = 10;
        JmImage.decodeImagePixels(rgba, width, height, num);

        // 3) 重新编码为 PNG
        final decodedImg = img.Image.fromBytes(
            width: width,
            height: height,
            bytes: rgba.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
        );
        final decodedPng = img.encodePng(decodedImg);
        decoded.writeAsBytesSync(decodedPng);
        print('已写出 decoded.png');

        // 4) 与 original.png 逐字节比对
        final originalBytes = original.readAsBytesSync();
        final originalImg = img.decodePng(originalBytes)!;
        final oW = originalImg.width;
        final oH = originalImg.height;
        expect(oW, equals(width), reason: '原图与 scrambled 宽不一致');
        expect(oH, equals(height), reason: '原图与 scrambled 高不一致');

        // 把 original 也转为 RGBA 后逐像素比对
        final oSrc4 = originalImg.numChannels == 4
            ? originalImg
            : originalImg.convert(numChannels: 4, alpha: 255);
        final oRgba = Uint8List(rgbaByteLen);
        final oData = oSrc4.data as img.ImageDataUint8;
        final oBytes = Uint8List.view(
            oData.data.buffer,
            oData.data.offsetInBytes,
            rgbaByteLen,
        );
        for (var i = 0; i < rgbaByteLen; i++)
        {
            oRgba[i] = oBytes[i];
        }

        // 逐字节比对（允许极小 JPEG 误差，但因为是 PNG 应该完全一致）
        var diffCount = 0;
        for (var i = 0; i < rgbaByteLen; i++)
        {
            if (oRgba[i] != rgba[i])
            {
                diffCount++;
            }
        }
        print('差异字节数: $diffCount / $rgbaByteLen');
        expect(diffCount, equals(0),
            reason: 'Dart 解密结果与 Python 原图存在 $diffCount 个差异字节，'
                '说明算法不一致');
        print('[OK] Dart decodeImagePixels 与 Python 解密结果像素级一致');
    });
}
