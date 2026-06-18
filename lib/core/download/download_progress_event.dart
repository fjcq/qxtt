part of 'download_service.dart';

/// 下载进度事件
class DownloadProgressEvent
{
    /// 任务 ID
    final String taskId;

    /// 当前已下载数
    final int current;

    /// 总数
    final int total;

    /// 下载速度
    final String speed;

    /// 进度 0.0 ~ 1.0
    final double progress;

    /// 任务状态（running/completed/failed/cancelled）
    final String status;

    /// 状态消息
    final String message;

    /// 本次任务涉及并已成功下载的 photoId 列表
    /// 仅在 status='completed' 时填充
    final List<String> downloadedPhotoIds;

    /// 已有部分图片下载的章节 photoId 列表
    /// 用于"边下边看"：任意一张图下载成功即把对应章节加入此列表
    final List<String> partialDownloadedPhotoIds;

    /// 本子作者（仅 album 任务且完成时填充）
    final String author;

    /// 本子页数（仅 album 任务且完成时填充）
    final int pageCount;

    /// 本子章节数（仅 album 任务且完成时填充）
    final int episodeCount;

    /// 本子本地封面路径（仅 album 任务且完成时填充）
    final String localCoverPath;

    /// 本子本地下载根目录（仅 album 任务且完成时填充）
    final String localPath;

    const DownloadProgressEvent({
        required this.taskId,
        required this.current,
        required this.total,
        required this.speed,
        required this.progress,
        required this.status,
        required this.message,
        this.downloadedPhotoIds = const [],
        this.partialDownloadedPhotoIds = const [],
        this.author = '',
        this.pageCount = 0,
        this.episodeCount = 0,
        this.localCoverPath = '',
        this.localPath = '',
    });
}
