import '../data/models/download_task_model.dart';

/// 下载任务状态分组
/// 已完成（completed）任务在 2 秒后自动从列表中移除，
/// 因此下载 Tab 上只展示 active 与 failed 两种分组
enum DownloadTaskGroup
{
    /// 正在下载（running + pending）
    active,

    /// 失败 / 取消
    failed,
}

/// 下载任务展示模型
/// 包装 [DownloadTaskModel]，附带派生的展示字段（状态分组、显示标题等）
class DownloadTaskView
{
    final DownloadTaskModel task;

    const DownloadTaskView(this.task);

    /// 任务显示标题
    String get displayTitle
    {
        final t = task.title;
        if (t != null && t.isNotEmpty) return t;
        return task.jmId;
    }

    /// 是否处于活动状态（运行中或等待中）
    bool get isActive => task.status == 'running' || task.status == 'pending';

    /// 是否失败或被取消
    bool get isFailed => task.status == 'failed' || task.status == 'cancelled';

    /// 是否可重试（failed / cancelled 任务可重试）
    bool get isRetryable => isFailed;

    /// 任务分组（completed 不参与分组，会被自动移除）
    DownloadTaskGroup get group
    {
        if (isActive) return DownloadTaskGroup.active;
        return DownloadTaskGroup.failed;
    }

    /// 是否为整本下载
    bool get isAlbumTask => task.taskType == 'album';
}
