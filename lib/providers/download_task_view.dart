import '../data/models/download_task_model.dart';

/// 下载任务状态分组
/// 已完成（completed）任务在 2 秒后自动从列表中移除，
/// 因此下载 Tab 上只展示 active、paused、failed 三种分组
enum DownloadTaskGroup
{
    /// 正在下载（running + pending）
    active,

    /// 已暂停
    paused,

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

    /// 是否已暂停
    bool get isPaused => task.status == 'paused';

    /// 是否失败或被取消
    bool get isFailed => task.status == 'failed' || task.status == 'cancelled';

    /// 是否可重试（failed / cancelled / paused 任务均可重试或继续）
    bool get isRetryable =>
        task.status == 'failed' ||
        task.status == 'cancelled' ||
        task.status == 'paused';

    /// 任务分组（completed 不参与分组，会被自动移除）
    DownloadTaskGroup get group
    {
        if (isActive) return DownloadTaskGroup.active;
        if (isPaused) return DownloadTaskGroup.paused;
        return DownloadTaskGroup.failed;
    }

    /// 是否为整本下载
    bool get isAlbumTask => task.taskType == 'album';

    /// 是否已有可阅读内容
    ///
    /// 满足任一条件即可阅读：
    /// - 整本任务：已有部分下载的章节（任意一张图即可进入阅读，缺失页走网络）
    /// - 单章任务：当前已下载了至少 1 张图片
    bool get hasReadableContent
    {
        if (isAlbumTask)
        {
            if (task.downloadedPhotoIds.isNotEmpty) return true;
            return task.partialDownloadedPhotoIds.isNotEmpty;
        }
        return task.currentImage > 0;
    }

    /// 获取推荐阅读的 photoId
    ///
    /// - 整本任务：优先返回第一个已完整下载的章节；没有则返回第一个有部分下载的章节
    /// - 单章任务：返回任务对应的 jmId（即 photoId）
    /// 没有可阅读内容时返回 null
    String? get readablePhotoId
    {
        if (!hasReadableContent) return null;
        if (isAlbumTask)
        {
            if (task.downloadedPhotoIds.isNotEmpty)
            {
                return task.downloadedPhotoIds.first;
            }
            if (task.partialDownloadedPhotoIds.isNotEmpty)
            {
                return task.partialDownloadedPhotoIds.first;
            }
            return task.firstPhotoId;
        }
        return task.jmId;
    }
}
