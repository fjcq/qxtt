/// 单本漫画的本地占用统计
class AlbumDiskStats
{
    /// 占用的字节数
    final int sizeBytes;

    /// 文件数
    final int fileCount;

    const AlbumDiskStats({required this.sizeBytes, required this.fileCount});

    /// 0 值哨兵
    static const empty = AlbumDiskStats(sizeBytes: 0, fileCount: 0);
}
