// 用 ui.instantiateImageCodec 解码 WebP 加密图，导出 RGBA raw bytes，
// 与 PIL 解码的 pil_raw_rgba.bin 字节级比对。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main()
{
    test('ui.instantiateImageCodec vs PIL 解码同一张 WebP 加密图',
        () async
    {
        final enc = File(r'e:\MyServer\JMComic\verify_assets\real_scrambled.jpg');
        final pilRaw = File(r'e:\MyServer\JMComic\verify_assets\pil_raw_rgba.bin');
        final dartRaw = File(r'e:\MyServer\JMComic\verify_assets\dart_raw_rgba.bin');
        expect(enc.existsSync(), isTrue);
        expect(pilRaw.existsSync(), isTrue);

        final encBytes = enc.readAsBytesSync();
        final pilBytes = pilRaw.readAsBytesSync();
        print('PIL raw size: ${pilBytes.length}');

        // 用平台 codec 解码
        final codec = await ui.instantiateImageCodec(
            Uint8List.fromList(encBytes),
        );
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;
        final width = uiImage.width;
        final height = uiImage.height;
        print('Dart codec 解码: ${width}x$height');

        final byteData = await uiImage.toByteData(
            format: ui.ImageByteFormat.rawRgba,
        );
        expect(byteData, isNotNull);
        final rgbaBytes = byteData!.buffer.asUint8List();
        print('Dart RGBA size: ${rgbaBytes.length}');
        expect(rgbaBytes.length, equals(pilBytes.length),
            reason: '尺寸不一致，无法比对');

        dartRaw.writeAsBytesSync(rgbaBytes);

        // 字节级比对
        var diff = 0;
        var maxDelta = 0;
        var firstDeltaIdx = -1;
        for (var i = 0; i < rgbaBytes.length; i++)
        {
            if (rgbaBytes[i] != pilBytes[i])
            {
                diff++;
                final d = (rgbaBytes[i] - pilBytes[i]).abs();
                if (d > maxDelta) maxDelta = d;
                if (firstDeltaIdx < 0)
                {
                    firstDeltaIdx = i;
                }
            }
        }
        print('差异字节: $diff / ${rgbaBytes.length} (max delta=$maxDelta)');

        // 抽几个特征点对比
        final w = width;
        final h = height;
        for (final y in [10, h ~/ 4, h ~/ 2, h * 3 ~/ 4, h - 10])
        {
            final idx = (y * w + w ~/ 2) * 4;
            final pilR = pilBytes[idx];
            final pilG = pilBytes[idx + 1];
            final pilB = pilBytes[idx + 2];
            final pilA = pilBytes[idx + 3];
            final dartR = rgbaBytes[idx];
            final dartG = rgbaBytes[idx + 1];
            final dartB = rgbaBytes[idx + 2];
            final dartA = rgbaBytes[idx + 3];
            print('  y=$y x=${w ~/ 2}: '
                'PIL=($pilR,$pilG,$pilB,$pilA) '
                'Dart=($dartR,$dartG,$dartB,$dartA)');
        }

        uiImage.dispose();
        codec.dispose();

        if (diff == 0)
        {
            print('[OK] 两个解码器字节级完全一致');
        }
        else
        {
            print('[INFO] 解码器有差异 (max=$maxDelta)');
        }
    });
}
