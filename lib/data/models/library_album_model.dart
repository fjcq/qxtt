/// 书架收藏模型
class LibraryAlbumModel
{
    /// 本子 ID
    late String albumId;

    /// 标题
    late String title;

    /// 作者
    late String author;

    /// 封面路径
    late String coverPath;

    /// 本地下载路径
    late String localPath;

    /// 页数
    late int pageCount;

    /// 章节数
    late int episodeCount;

    /// 添加时间
    late String addedAt;

    /// 最后阅读时间
    String? lastReadAt;

    /// 最后阅读页码
    late int lastReadPage;
}
