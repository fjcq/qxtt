import '../data/models/download_task_model.dart';
import 'download_task_view.dart';

/// 下载管理状态
class DownloadState
{
    /// 所有下载任务（含短暂的 completed 任务）
    final List<DownloadTaskModel> tasks;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    /// 最近一次完成的任务（用于 UI 弹 SnackBar）
    final DownloadTaskModel? lastCompletedTask;

    /// 完成事件序号，UI 用其差值判断是否要弹新 SnackBar
    final int completionCounter;

    const DownloadState({
        this.tasks = const [],
        this.isLoading = false,
        this.error,
        this.lastCompletedTask,
        this.completionCounter = 0,
    });

    /// 按状态分组
    /// 已完成任务不出现在分组中（由 UI 与状态隔离，避免视觉重复）
    Map<DownloadTaskGroup, List<DownloadTaskView>> get grouped
    {
        final map = <DownloadTaskGroup, List<DownloadTaskView>>{
            DownloadTaskGroup.active: [],
            DownloadTaskGroup.paused: [],
            DownloadTaskGroup.failed: [],
        };
        for (final t in tasks)
        {
            // completed 任务不进入任何分组（2 秒后会被自动归档）
            if (t.status == 'completed') continue;
            final v = DownloadTaskView(t);
            map[v.group]!.add(v);
        }
        return map;
    }

    /// 总计活动任务数
    int get activeCount
    {
        var n = 0;
        for (final t in tasks)
        {
            if (t.status == 'running' || t.status == 'pending') n++;
        }
        return n;
    }

    /// 总计已暂停任务数
    int get pausedCount
    {
        var n = 0;
        for (final t in tasks)
        {
            if (t.status == 'paused') n++;
        }
        return n;
    }

    /// 总计失败 / 取消任务数
    int get failedCount
    {
        var n = 0;
        for (final t in tasks)
        {
            if (t.status == 'failed' || t.status == 'cancelled') n++;
        }
        return n;
    }

    DownloadState copyWith({
        List<DownloadTaskModel>? tasks,
        bool? isLoading,
        String? error,
        DownloadTaskModel? lastCompletedTask,
        int? completionCounter,
    })
    {
        return DownloadState(
            tasks: tasks ?? this.tasks,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            lastCompletedTask: lastCompletedTask ?? this.lastCompletedTask,
            completionCounter: completionCounter ?? this.completionCounter,
        );
    }
}
