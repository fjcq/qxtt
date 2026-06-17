// 用真实 jmcomic 加密图 + 真实参数（aid=1440552, filename=00001, num=14）
// 直接调用 JmImage.decode（使用 ui.instantiateImageCodec 平台原生解码器），
// 输出 dart_decoded.jpg，然后与 Python 端 expected_decoded.png 像素级比对。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    test('真实 jmcomic 加密图 num=14 → JmImage.decode vs Python',
        () async
    {
        final enc = File(r'e:\MyServer\JMComic\verify_assets\real_scrambled.jpg');
        final expected = File(r'e:\MyServer\JMComic\verify_assets\expected_decoded.png');
        final out = File(r'e:\MyServer\JMComic\verify_assets\dart_decoded.jpg');
        expect(enc.existsSync(), isTrue);
        expect(expected.existsSync(), isTrue);

        // 1) 直接调用 JmImage.decode
        final encBytes = enc.readAsBytesSync();
        print('加密图字节: ${encBytes.length}');

        final decodedBytes = await JmImage.decode(
            Uint8List.fromList(encBytes),
            220000,  // scramble_id（猜测，但 num>0 不依赖具体值）
            1440552, // aid = photoId
            '00001',
        );
        out.writeAsBytesSync(decodedBytes);
        print('已写出 dart_decoded.jpg (${decodedBytes.length} bytes)');

        // 2) 读取 expected_decoded.png 转为 RGBA 比对
        final expBytes = expected.readAsBytesSync();
        final expImg = img.decodePng(expBytes)!;
        final w = expImg.width;
        final h = expImg.height;
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

        // 3) 解码 dart_decoded.jpg 为 RGBA
        final dartImg = img.decodeJpg(decodedBytes)!;
        print('dart 解码后: ${dartImg.width}x${dartImg.height}');
        expect(dartImg.width, equals(w));
        expect(dartImg.height, equals(h));
        final d4 = dartImg.numChannels == 4
            ? dartImg
            : dartImg.convert(numChannels: 4, alpha: 255);
        final dData = d4.data as img.ImageDataUint8;
        final dRgba = Uint8List(eLen);
        final dView = Uint8List.view(
            dData.data.buffer, dData.data.offsetInBytes, eLen,
        );
        for (var i = 0; i < eLen; i++) dRgba[i] = dView[i];

        // 4) 逐字节比对（容忍 JPEG 压缩损失 < 5）
        var diff = 0;
        var maxDelta = 0;
        for (var i = 0; i < eLen; i++)
        {
            if (dRgba[i] != eRgba[i])
            {
                diff++;
                final d = (dRgba[i] - eRgba[i]).abs();
                if (d > maxDelta) maxDelta = d;
            }
        }
        print('差异字节: $diff / $eLen (max delta=$maxDelta)');

        if (maxDelta < 5)
        {
            print('[OK] Dart JmImage.decode 与 Python 真实解密结果在 JPEG 容差内一致');
        }
        else
        {
            print('[FAIL] 不一致 — max delta=$maxDelta');
        }
    });
}
