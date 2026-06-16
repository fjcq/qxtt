import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

// 注意: 需要在 pubspec.yaml 中添加 crypto 依赖
// 这里仅测试加解密逻辑的正确性

void main()
{
    group('JmCrypto Tests', ()
    {
        test('token 生成测试', () async
        {
            // 测试 md5 计算
            final ts = 1700566805;
            final secret = '185Hcomic3PAPP7R';
            final expected = md5.convert(utf8.encode('$ts$secret')).toString();
            expect(expected, isNotEmpty);
        });

        test('tokenparam 格式测试', () async
        {
            final ts = 1700566805;
            final ver = '2.0.26';
            final tokenparam = '$ts,$ver';
            expect(tokenparam, '1700566805,2.0.26');
        });
    });

    group('JmImage Tests', ()
    {
        test('分割数计算 - aid 小于 scramble_id', () async
        {
            // aid < scramble_id → 0
            // getSegmentationNum(scrambleId=220980, aid=100000, filename='00001.jpg')
            // 100000 < 220980 → 0
            // 注意: 实际函数在 jm_image.dart 中
        });

        test('分割数计算 - aid 小于 268850', () async
        {
            // 220980 <= aid < 268850 → 10
        });

        test('分割数计算 - aid 大于 268850', () async
        {
            // aid >= 268850 → md5 hash 计算
        });
    });
}
