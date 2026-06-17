// 验证 JmImage.decodeImagePixels 算法正确性
// 1) 生成已知原图（每行填上不同颜色）
// 2) 模拟加密：执行"反向重排"（与解密互为逆操作）
// 3) 执行解密：调用 decodeImagePixels
// 4) 验证结果与原图一致
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    group('decodeImagePixels 算法自洽性', ()
    {
        test('小尺寸 - 偶数分割', () {
            _verifyRoundTrip(width: 10, height: 100, num: 10);
        });

        test('中尺寸 - 包含余数', () {
            _verifyRoundTrip(width: 80, height: 105, num: 10);
        });

        test('大尺寸 - 偶数分割', () {
            _verifyRoundTrip(width: 200, height: 1000, num: 10);
        });

        test('边界 - num=2', () {
            _verifyRoundTrip(width: 50, height: 200, num: 2);
        });
    });
}

/// 执行一次完整往返：原图 → 模拟加密 → 解密 → 验证等于原图
void _verifyRoundTrip({
    required int width,
    required int height,
    required int num,
})
{
    // 1. 构造原图：每行 y 用 y.toInt() 的 RGBA 表示
    final original = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++)
    {
        for (var x = 0; x < width; x++)
        {
            final off = (y * width + x) * 4;
            // 用 R = 高字节、G/B 区分行号，避免对称像素干扰比对
            original[off]     = y & 0xFF;
            original[off + 1] = ((y >> 8) * 7) & 0xFF;
            original[off + 2] = x & 0xFF;
            original[off + 3] = 255;
        }
    }

    // 2. 模拟加密：执行解密的逆操作
    // 解密把 Encrypted[h-move-over:h-over] → Decoded[0:move+over]
    // 因此加密就是把 Decoded[0:move+over] → Encrypted[h-move-over:h-over]
    final encrypted = _simulateEncryption(original, width, height, num);

    // 3. 执行解密
    final decoded = Uint8List.fromList(encrypted);
    JmImage.decodeImagePixels(decoded, width, height, num);

    // 4. 验证
    for (var i = 0; i < original.length; i++)
    {
        expect(
            decoded[i],
            original[i],
            reason: 'byte index=$i (w=$width h=$height num=$num)',
        );
    }
}

/// 模拟 JMComic 服务端的加密（与 decodeImagePixels 互逆）
///
/// 解密规则（decodeImagePixels）:
///   ySrc = h - move*(i+1) - over
///   yDst = move*i (+ over if i>0)
///   actualH = move+over (i=0) | move (i>0)
///   Encrypted[ySrc..ySrc+actualH] -> Decoded[yDst..yDst+actualH]
///
/// 加密为解密的逆操作: Decoded[yDst..yDst+actualH] -> Encrypted[ySrc..ySrc+actualH]
/// 即 Original[same as yDst range] -> Encrypted[same as ySrc range]
Uint8List _simulateEncryption(Uint8List src, int width, int height, int num)
{
    final dst = Uint8List(src.length);
    final over = height % num;
    for (var i = 0; i < num; i++)
    {
        final moveVal = height ~/ num;
        int ySrc, yDst, h;
        if (i == 0)
        {
            ySrc = height - moveVal - over;   // 反向：解密时 dst 来自这里
            yDst = 0;                          // 反向：解密时 src 在这里
            h = moveVal + over;
        }
        else
        {
            ySrc = height - moveVal * (i + 1) - over;
            yDst = moveVal * i + over;
            h = moveVal;
        }
        for (var row = 0; row < h; row++)
        {
            for (var x = 0; x < width; x++)
            {
                final sOff = ((yDst + row) * width + x) * 4;
                final dOff = ((ySrc + row) * width + x) * 4;
                dst[dOff]     = src[sOff];
                dst[dOff + 1] = src[sOff + 1];
                dst[dOff + 2] = src[sOff + 2];
                dst[dOff + 3] = src[sOff + 3];
            }
        }
    }
    return dst;
}
