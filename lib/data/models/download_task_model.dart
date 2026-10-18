/// 章节级下载进度
///
/// 记录单个章节（photoId）的图片完成数与总页数，
/// 仅在内存中传递与展示，不持久化
class ChapterProgress
{
    /// 已完成的图片数
    final int completed;

    /// 章节总页数
    final int total;

    const ChapterProgress({
        required this.completed,
        required this.total,
    });

    /// 进度比例 0.0 ~ 1.0（总页数为 0 时返回 0）
    double get ratio => total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    /// 是否已完成
    bool get isComplete => total > 0 && completed >= total;
}

/// 下载任务模型
class DownloadTaskModel
{
    /// 任务唯一 ID
    String taskId = '';

    /// 任务类型: "album" | "photo"
    String taskType = '';

    /// 禁漫 ID
    /// - taskType=='album' 时为 albumId
    /// - taskType=='photo' 时为 photoId
    String jmId = '';

    /// 所属本子 ID
    /// - taskType=='album' 时等于 jmId
    /// - taskType=='photo' 时为父本子 ID
    String albumId = '';

    /// 本子标题（用于构建本地目录）
    String albumTitle = '';

    /// 章节序号（单章任务）
    String episodeIndex = '';

    /// 章节名称（单章任务）
    String episodeName = '';

    /// 已下载的章节 photoId 列表（任务完成后由服务填充）
    /// 仅在内存中传递，不持久化
    List<String> downloadedPhotoIds = const [];

    /// 已有部分图片下载的章节 photoId 列表
    /// 用于"边下边看"：任意一张图成功下载后即把对应章节加入此集合，
    /// 区别于 [downloadedPhotoIds]（仅在章节全部完成时追加）
    List<String> partialDownloadedPhotoIds = const [];

    /// 章节级进度映射（photoId → 进度）
    ///
    /// - album 任务：每个章节各自的已完成页数 / 总页数
    /// - photo 任务：仅包含该任务对应的单章
    /// 仅在内存中传递（由进度事件实时填充），不持久化
    Map<String, ChapterProgress> chapterProgress = const {};

    /// 任务状态: "pending" | "running" | "completed" | "failed" | "cancelled"
    String status = 'pending';

    /// 状态消息
    String message = '';

    /// 创建时间
    String createdAt = '';

    /// 更新时间
    String updatedAt = '';

    /// 下载进度 0.0 ~ 1.0
    double progress = 0.0;

    /// 当前已下载图片数
    int currentImage = 0;

    /// 总图片数
    int totalImages = 0;

    /// 漫画标题
    String? title;

    /// 封面路径
    String? coverPath;

    /// 第一话 photoId（album 任务下载完成后填入）
    String? firstPhotoId;

    /// 下载速度（仅运行时使用，不持久化）
    String speed = '';

    // === 以下字段用于在完成时携带 album 元信息，供 library 显示 ===
    // 字段名复用"cover"前缀仅表示与已下载封面展示相关的元数据，
    // 不影响原有 coverPath 字段语义（coverPath 是本地封面文件路径）。

    /// 本子作者（仅 album 任务）
    String coverAuthor = '';

    /// 本子页数（仅 album 任务）
    int coverPageCount = 0;

    /// 本子章节数（仅 album 任务）
    int coverEpisodeCount = 0;

    /// 本子本地下载根目录（仅 album 任务）
    String localPath = '';

    /// 任务来源（统一阅读架构）
    ///
    /// 取值：
    /// - `manual`：用户主动下载（默认值，兼容旧数据）
    /// - `reading`：阅读产生的下载任务
    ///
    /// 下载管理页面据此显示来源标记并支持按来源筛选；
    /// "一键清理阅读产生任务"功能也依赖此字段。
    String source = 'manual';
}
