import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 禁漫图片分割解密工具
class JmImage
{
    /// 计算图片分割数
    /// 规则:
    /// - aid < scramble_id → 0 (无需解密)
    /// - aid < 268850 → 10
    /// - aid < 421926 → x=10, 否则 x=8
    ///   num = md5("{aid}{filename}") 最后一个字符的 codeUnit % x * 2 + 2
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
        final x = aid < 421926 ? 10 : 8;
        final hash = md5.convert(utf8.encode('$aid$filename')).toString();
        final lastChar = hash.codeUnitAt(hash.length - 1);
        final num = lastChar % x;
        return num * 2 + 2;
    }

    /// 图片分割解密（像素级操作）
    /// 将图片按高度分成 num 段，重新排列
    /// [imageBytes] 原始图片字节
    /// [num] 分割数
    /// 返回解密后的图片字节
    static List<int> decodeImagePixels(
        List<int> imageBytes,
        int width,
        int height,
        int num,
    )
    {
        if (num == 0 || imageBytes.isEmpty)
        {
            return imageBytes;
        }

        final pixels = Uint32List.fromList(
            imageBytes is Uint32List
                ? imageBytes as Uint32List
                : Uint32List.fromList(imageBytes.cast<int>()),
        );
        final decoded = Uint32List(pixels.length);
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

            // 逐行拷贝像素
            for (var row = 0; row < actualH; row++)
            {
                final srcOffset = (actualYSrc + row) * width;
                final dstOffset = (actualYDst + row) * width;
                for (var col = 0; col < width; col++)
                {
                    decoded[dstOffset + col] = pixels[srcOffset + col];
                }
            }
        }

        return decoded.toList();
    }

    // 私有构造函数，防止实例化
    JmImage._();
}
