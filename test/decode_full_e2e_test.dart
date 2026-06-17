// 完整 JmImage.decode 端到端验证：scambled.png → 平台解码 → 解密 → JPEG 编码
// 然后用 Python 反向校验 JPEG 字节是否真的是"已解密的图"。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    test('完整 JmImage.decode 端到端：scrambled.png → decoded.jpg',
        () async
    {
        final assetsDir = r'e:\MyServer\JMComic\verify_assets';
        final scrambledPng = File('$assetsDir\\scrambled.png');
        expect(scrambledPng.existsSync(), isTrue);

        final bytes = scrambledPng.readAsBytesSync();
        print('输入 scrambled.png: ${bytes.length} bytes');

        // aid=500000, filename=00013, scramble_id=220000 → num=10
        final decoded = await JmImage.decode(
            Uint8List.fromList(bytes),
            220000,
            500000,
            '00013',
        );

        print('输出 decoded.jpg: ${decoded.length} bytes, '
            '前 4 字节: ${decoded.take(4).toList()}');

        // JPEG 起始字节应为 0xFF 0xD8 0xFF
        expect(decoded[0], equals(0xFF));
        expect(decoded[1], equals(0xD8));
        expect(decoded[2], equals(0xFF));

        // 保存供 Python 端校验
        File('$assetsDir\\decoded.jpg').writeAsBytesSync(decoded);
        print('已写出 decoded.jpg');
    });
}
