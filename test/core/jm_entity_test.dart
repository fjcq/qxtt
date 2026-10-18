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

    group('FavoriteResult.fromJson', ()
    {
        test('total 为字符串时应容错解析（对齐接口实际返回 "87"）', ()
        {
            final json = <String, dynamic>{
                'list': [
                    {'id': '363859', 'name': '测试本子'},
                ],
                'total': '87',
                'count': 20,
            };

            final result = FavoriteResult.fromJson(json);

            expect(result.total, 87);
            expect(result.results.length, 1);
            expect(result.results.first.id, '363859');
        });

        test('total 为数字时正常解析，缺失时兜底为 0', ()
        {
            expect(FavoriteResult.fromJson({'list': [], 'total': 5}).total, 5);
            expect(FavoriteResult.fromJson({'list': []}).total, 0);
        });
    });

    group('SearchResult.fromJson', ()
    {
        test('total/page_count 为字符串时应容错解析', ()
        {
            final json = <String, dynamic>{
                'content': [
                    {'id': '400222', 'name': '搜索结果'},
                ],
                'total': '120',
                'page_count': '6',
            };

            final result = SearchResult.fromJson(json);

            expect(result.total, 120);
            expect(result.pageCount, 6);
            expect(result.results.length, 1);
        });
    });

    group('Episode.displayName', ()
    {
        test('name 非空时返回原始 name', ()
        {
            final episode = Episode.fromJson({
                'id': '413446',
                'sort': '2',
                'name': '第2話',
            });

            expect(episode.displayName, '第2話');
        });

        test('name 为空字符串时回退为 "第N话"', ()
        {
            final episode = Episode.fromJson({
                'id': '400222',
                'sort': '1',
                'name': '',
            });

            expect(episode.displayName, '第1话');
        });

        test('name 仅含空白时回退为 "第N话"', ()
        {
            final episode = Episode.fromJson({
                'id': '413447',
                'sort': '3',
                'name': '   ',
            });

            expect(episode.displayName, '第3话');
        });

        test('name 与 sort 均缺失时兜底为 "未命名章节"', ()
        {
            final episode = Episode.fromJson({
                'id': '413448',
            });

            expect(episode.displayName, '未命名章节');
        });
    });
}
