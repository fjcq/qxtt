import '../data/database/library_dao.dart';
import '../data/models/library_album_model.dart';
import '../utils/library_storage.dart';
import 'library_notifier_base.dart';

/// 书架读取与刷新 mixin
/// 负责加载书架、扫描目录、刷新本地占用统计等只读/刷新类操作
mixin LibraryReadMixin on LibraryNotifierBase
{
    /// 加载书架
    @override
    Future<void> loadLibrary() async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final albums = await libraryDao.getAllAlbums();
            state = state.copyWith(albums: albums, isLoading: false);
            // 异步刷新本地占用统计（不阻塞主流程）
            refreshAllSizeStats();
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 扫描下载目录，更新书架
    Future<void> refreshLibrary(String downloadDir) async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            await libraryDao.syncFromDirectory(downloadDir);
            final albums = await libraryDao.getAllAlbums();
            state = state.copyWith(albums: albums, isLoading: false);
            await refreshAllSizeStats();
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 刷新所有 album 的本地占用统计
    /// 先读 downloadDir，再批量扫描本地目录，更新 state 与 DAO
    Future<void> refreshAllSizeStats() async
    {
        if (state.albums.isEmpty) return;
        try
        {
            final downloadDir = await resolveDownloadDir();
            final statsMap = await LibraryStorage.computeBatchDiskUsage(
                state.albums,
                downloadDir: downloadDir,
            );
            // 写回 DAO 持久化
            final persistMap = <String, AlbumSizeStats>{};
            statsMap.forEach((id, stats)
            {
                persistMap[id] =
                    AlbumSizeStats(sizeBytes: stats.sizeBytes, fileCount: stats.fileCount);
            });
            await libraryDao.updateAlbumsSize(persistMap);
            // 同步刷新内存中的 albums
            final updated = state.albums.map((album)
            {
                final s = statsMap[album.albumId];
                if (s == null) return album;
                return album
                    ..sizeBytes = s.sizeBytes
                    ..fileCount = s.fileCount;
            }).toList();
            if (mounted)
            {
                state = state.copyWith(albums: updated);
            }
        }
        catch (_)
        {
            // 占用刷新失败不影响主流程
        }
    }

    /// 刷新单本漫画的本地占用
    Future<void> refreshAlbumSizeStats(String albumId) async
    {
        final album = state.albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return;
        try
        {
            final downloadDir = await LibraryStorage.getDownloadDir();
            final stats = await LibraryStorage.computeDiskUsage(
                await LibraryStorage.resolveAlbumDir(album, downloadDir: downloadDir),
            );
            album
                ..sizeBytes = stats.sizeBytes
                ..fileCount = stats.fileCount;
            await libraryDao.updateAlbumSize(
                albumId,
                sizeBytes: stats.sizeBytes,
                fileCount: stats.fileCount,
            );
            if (mounted)
            {
                // 触发 setState 刷新
                state = state.copyWith(albums: List.from(state.albums));
            }
        }
        catch (_)
        {
            // 忽略
        }
    }

    /// 根据 albumId 获取书架项
    Future<LibraryAlbumModel?> getByAlbumId(String albumId) async
    {
        return libraryDao.getByAlbumId(albumId);
    }

    /// 获取所有书架项
    Future<List<LibraryAlbumModel>> getAllAlbums() async
    {
        return libraryDao.getAllAlbums();
    }
}
