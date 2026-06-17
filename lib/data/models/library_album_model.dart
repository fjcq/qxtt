/// 书架收藏模型
/// 所有 String/num 字段使用默认值（空串/0），避免因未初始化触发
/// LateInitializationError。历史版本数据可能因 JSON 解析异常而部分字段缺失，
/// 此时应优雅降级为默认值而不是抛异常中断业务流程（如删除）
class LibraryAlbumModel
{
    /// 本子 ID
    String albumId = '';

    /// 标题
    String title = '';

    /// 作者
    String author = '';

    /// 封面路径
    String coverPath = '';

    /// 本地下载路径
    String localPath = '';

    /// 页数
    int pageCount = 0;

    /// 章节数
    int episodeCount = 0;

    /// 已下载的章节 ID 列表
    List<String> downloadedEpisodes = const [];

    /// 添加时间
    String addedAt = '';

    /// 最后阅读时间
    String? lastReadAt;

    /// 最后阅读页码
    int lastReadPage = 0;

    /// 本地占用空间（字节），0 表示未知
    int sizeBytes = 0;

    /// 本地图片文件数量，0 表示未知
    int fileCount = 0;
}
