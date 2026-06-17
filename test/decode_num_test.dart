// 验证 JmImage.getSegmentationNum 与 Python 库对齐
// Python 参考: src/jmcomic/jm_toolkit.py: JmImageTool.get_num
// Python 库通过 of_file_name(url, True) / JmImageDetail.img_file_name
// 拿到的是去后缀的 filename（与 Dart 端去后缀逻辑对齐）
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic_mobile/core/jm/jm_image.dart';

void main()
{
    group('getSegmentationNum 与 Python 库对齐', ()
    {
        test('1440552 / scrambleId=220980: filename=00001.webp 应得 num=14', ()
        {
            // Python 库实测: JmImageTool.get_num(220980, 1440552, '00001.webp')=14
            // 因为 getSegmentationNum 内部会去后缀，所以 '00001.webp' 和 '00001' 都应得 num=14
            // 关键验证：python_src/00001.webp (109129 bytes) 本身是行重排错乱的
            // (JM 服务端对 1440552 章节做了 scramble_id=220980 加密)，
            // 跑 num=14 解密才得到真图。aid(1440552) > scramble_id(220980)
            // 必须走加密分支。
            final n1 = JmImage.getSegmentationNum(220980, 1440552, '00001.webp');
            final n2 = JmImage.getSegmentationNum(220980, 1440552, '00001');
            expect(n1, 14, reason: '带后缀应被去后缀，得到 num=14');
            expect(n2, 14, reason: '已去后缀应得 num=14');
        });

        test('aid < scrambleId 应得 num=0', ()
        {
            expect(JmImage.getSegmentationNum(300000, 100, '00001.webp'), 0);
        });

        test('aid < 268850 应得 num=10', ()
        {
            // aid < scrambleId 必须先满足；这里 scrambleId=100 < aid=200000
            expect(JmImage.getSegmentationNum(100, 200000, '00001.webp'), 10);
        });
    });
}
