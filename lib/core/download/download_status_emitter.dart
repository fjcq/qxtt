part of 'download_service.dart';

/// 负责向进度流发送下载状态/进度事件
extension DownloadServiceStatusEmitter on DownloadService
{
    /// 发送进度事件
    void _emitProgress(
        String taskId,
        int current,
        int total,
        double progress,
        String status,
        String message, {
        String? photoId,
    })
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: current,
            total: total,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
            photoId: photoId,
        ));
    }

    /// 发送状态变更事件（用于完成/失败/取消等状态）
    void _emitStatus(
        String taskId,
        String status,
        String message,
        double progress, {
        String? photoId,
    })
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: 0,
            total: 0,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
            photoId: photoId,
        ));
    }

    /// 发送带附加负载的状态事件
    /// 用于完成时回传 photoId 列表与 album 元信息
    void _emitStatusWithPayload(
        String taskId,
        String status,
        String message,
        double progress,
        List<String> downloadedPhotoIds, {
        String author = '',
        int pageCount = 0,
        int episodeCount = 0,
        String localCoverPath = '',
        String localPath = '',
        String? photoId,
    })
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: 0,
            total: 0,
            speed: speed,
            progress: progress,
            status: status,
            message: message,
            downloadedPhotoIds: downloadedPhotoIds,
            author: author,
            pageCount: pageCount,
            episodeCount: episodeCount,
            localCoverPath: localCoverPath,
            localPath: localPath,
            photoId: photoId,
        ));
    }

    /// 发送单页完成事件（统一阅读专用）
    ///
    /// 当 [ConcurrentImageDownloader] 完成单张图片下载并写盘后调用，
    /// 携带 [photoId] 与 [filename] 让阅读器精确定位刷新对应页。
    /// 不更新任务级统计（避免与 [reportProgress] 重复统计），
    /// 仅作为"页面就绪"信号广播给当前章节的订阅者。
    void _emitPageCompleted(
        String taskId,
        String photoId,
        String filename,
        int current,
        int total,
        double progress,
    )
    {
        final stats = _taskStats[taskId];
        final speed = stats != null ? _formatSpeed(stats.getSpeed()) : '';
        _progressController.add(DownloadProgressEvent(
            taskId: taskId,
            current: current,
            total: total,
            speed: speed,
            progress: progress,
            status: 'pageCompleted',
            message: '页下载完成',
            photoId: photoId,
            completedFilename: filename,
        ));
    }

    /// 格式化下载速度
    static String _formatSpeed(double bytesPerSecond)
    {
        if (bytesPerSecond <= 0) return '';
        if (bytesPerSecond < 1024)
        {
            return '${bytesPerSecond.toStringAsFixed(0)} B/s';
        }
        else if (bytesPerSecond < 1024 * 1024)
        {
            return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
        }
        else
        {
            return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
        }
    }
}

/// 下载统计信息（用于计算下载速度）
class _DownloadStats
{
    /// 下载开始时间
    final DateTime _startTime = DateTime.now();

    /// 已下载总字节数
    int _totalBytes = 0;

    /// 添加已下载字节数
    void addBytes(int bytes)
    {
        _totalBytes += bytes;
    }

    /// 计算下载速度（字节/秒）
    double getSpeed()
    {
        final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
        if (elapsed <= 0) return 0.0;
        return _totalBytes / (elapsed / 1000.0);
    }
}
