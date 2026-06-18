import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic_mobile/core/jm/jm_entity.dart';

void main()
{
    group('AlbumDetail.fromJson', ()
    {
        test('应从 series 长度计算 episodeCount，且单章时自成一章', ()
        {
            final json = <String, dynamic>{
                'id': '400222',
                'name': '测试本子',
                'author': '测试作者',
                'series': [
                    {'id': '400222', 'sort': '1', 'name': ''},
                    {'id': '413446', 'sort': '2', 'name': '第2話'},
                    {'id': '413447', 'sort': '3', 'name': '第3話'},
                ],
                'tags': <String>[],
                'total_views': '1000',
                'likes': '10',
                'comment_total': '5',
                'description': '',
            };

            final detail = AlbumDetail.fromJson(json);

            expect(detail.albumId, '400222');
            expect(detail.episodes.length, 3);
            expect(detail.episodeCount, 3);
        });

        test('series 为空时应自成一章，episodeCount 为 1', ()
        {
            final json = <String, dynamic>{
                'id': '438516',
                'name': '单章本子',
                'author': '测试作者',
                'series': <dynamic>[],
                'tags': <String>[],
                'total_views': '1000',
                'likes': '10',
                'comment_total': '5',
                'description': '',
            };

            final detail = AlbumDetail.fromJson(json);

            expect(detail.episodes.length, 1);
            expect(detail.episodeCount, 1);
            expect(detail.episodes.first.photoId, '438516');
            expect(detail.episodes.first.index, '1');
        });

        test('page_count 字段存在时应正确解析', ()
        {
            final json = <String, dynamic>{
                'id': '438516',
                'name': '单章本子',
                'author': '测试作者',
                'series': <dynamic>[],
                'page_count': 42,
                'tags': <String>[],
                'total_views': '1000',
                'likes': '10',
                'comment_total': '5',
                'description': '',
            };

            final detail = AlbumDetail.fromJson(json);

            expect(detail.pageCount, 42);
        });
    });
}
