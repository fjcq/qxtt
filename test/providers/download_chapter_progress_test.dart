import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic_mobile/data/models/download_task_model.dart';
import 'package:jmcomic_mobile/providers/download_task_view.dart';

/// 构造一个指定字段的最小下载任务模型
DownloadTaskModel _makeTask({
    String taskId = 't1',
    String taskType = 'album',
    String jmId = '100',
    String albumId = '100',
    String status = 'running',
    Map<String, ChapterProgress> chapterProgress = const {},
})
{
    final task = DownloadTaskModel()
      ..taskId = taskId
      ..taskType = taskType
      ..jmId = jmId
      ..albumId = albumId
      ..status = status
      ..chapterProgress = chapterProgress;
    return task;
}

void main()
{
    group('ChapterProgress 值对象', ()
    {
        test('ratio 按已完成/总数计算并夹取到 0~1', ()
        {
            const p = ChapterProgress(completed: 12, total: 30);
            expect(p.ratio, closeTo(0.4, 1e-9));
            expect(p.isComplete, isFalse);
        });

        test('总数为 0 时 ratio 为 0 且不算完成', ()
        {
            const p = ChapterProgress(completed: 5, total: 0);
            expect(p.ratio, 0.0);
            expect(p.isComplete, isFalse);
        });

        test('完成数达到总数时判定完成', ()
        {
            const p = ChapterProgress(completed: 30, total: 30);
            expect(p.isComplete, isTrue);
            expect(p.ratio, 1.0);
        });
    });

    group('DownloadTaskStatusX 状态扩展', ()
    {
        test('running/pending 为活动状态', ()
        {
            expect(_makeTask(status: 'running').isActive, isTrue);
            expect(_makeTask(status: 'pending').isActive, isTrue);
            expect(_makeTask(status: 'paused').isActive, isFalse);
        });

        test('paused 判定', ()
        {
            expect(_makeTask(status: 'paused').isPaused, isTrue);
            expect(_makeTask(status: 'running').isPaused, isFalse);
        });

        test('completed/failed/cancelled 为终结状态', ()
        {
            expect(_makeTask(status: 'completed').isFinal, isTrue);
            expect(_makeTask(status: 'failed').isFinal, isTrue);
            expect(_makeTask(status: 'cancelled').isFinal, isTrue);
            expect(_makeTask(status: 'running').isFinal, isFalse);
            expect(_makeTask(status: 'paused').isFinal, isFalse);
        });
    });

    group('firstAlbumTask 取整本任务', ()
    {
        test('存在整本任务时返回第一个', ()
        {
            final a = _makeTask(taskId: 'a', taskType: 'album');
            final b = _makeTask(taskId: 'b', taskType: 'album');
            final result = firstAlbumTask([a, b]);
            expect(result, same(a));
        });

        test('不存在整本任务时返回 null', ()
        {
            final photo = _makeTask(taskId: 'p', taskType: 'photo', jmId: '200');
            expect(firstAlbumTask([photo]), isNull);
        });

        test('空任务列表返回 null', ()
        {
            expect(firstAlbumTask([]), isNull);
        });
    });

    group('mergeChapterProgress 章节进度合并', ()
    {
        test('取整本任务的章节进度映射', ()
        {
            final album = _makeTask(
                taskType: 'album',
                chapterProgress: {
                    '101': const ChapterProgress(completed: 10, total: 20),
                    '102': const ChapterProgress(completed: 5, total: 15),
                },
            );
            final merged = mergeChapterProgress([album]);
            expect(merged['101']!.completed, 10);
            expect(merged['102']!.total, 15);
        });

        test('单章任务补充整本未覆盖的章节', ()
        {
            final album = _makeTask(
                taskType: 'album',
                chapterProgress: {
                    '101': const ChapterProgress(completed: 10, total: 20),
                },
            );
            final photo = _makeTask(
                taskType: 'photo',
                jmId: '300',
                albumId: '100',
                chapterProgress: {
                    '300': const ChapterProgress(completed: 3, total: 8),
                },
            );
            final merged = mergeChapterProgress([album, photo]);
            expect(merged.containsKey('101'), isTrue);
            expect(merged.containsKey('300'), isTrue);
            expect(merged['300']!.completed, 3);
        });

        test('整本已覆盖的章节不被单章进度覆盖（整本优先）', ()
        {
            final album = _makeTask(
                taskType: 'album',
                chapterProgress: {
                    '101': const ChapterProgress(completed: 10, total: 20),
                },
            );
            // 单章任务的 jmId 与整本映射中的章节重叠
            final photo = _makeTask(
                taskType: 'photo',
                jmId: '101',
                albumId: '100',
                chapterProgress: {
                    '101': const ChapterProgress(completed: 1, total: 2),
                },
            );
            final merged = mergeChapterProgress([album, photo]);
            expect(merged['101']!.total, 20);
            expect(merged['101']!.completed, 10);
        });

        test('仅有单章任务时返回单章进度', ()
        {
            final photo = _makeTask(
                taskType: 'photo',
                jmId: '300',
                albumId: '100',
                chapterProgress: {
                    '300': const ChapterProgress(completed: 3, total: 8),
                },
            );
            final merged = mergeChapterProgress([photo]);
            expect(merged.length, 1);
            expect(merged['300']!.total, 8);
        });

        test('任务无进度数据时返回空映射', ()
        {
            final album = _makeTask(taskType: 'album');
            expect(mergeChapterProgress([album]), isEmpty);
        });
    });
}
