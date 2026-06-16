/// 下载任务模型
class DownloadTaskModel
{
    /// 任务唯一 ID
    late String taskId;

    /// 任务类型: "album" | "photo"
    late String taskType;

    /// 禁漫 ID
    late String jmId;

    /// 任务状态: "pending" | "running" | "completed" | "failed" | "cancelled"
    late String status;

    /// 状态消息
    late String message;

    /// 创建时间
    late String createdAt;

    /// 更新时间
    late String updatedAt;

    /// 下载进度 0.0 ~ 1.0
    late double progress;

    /// 当前已下载图片数
    late int currentImage;

    /// 总图片数
    late int totalImages;

    /// 漫画标题
    String? title;

    /// 封面路径
    String? coverPath;
}
