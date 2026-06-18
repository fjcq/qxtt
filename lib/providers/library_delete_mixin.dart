import '../utils/library_storage.dart';
import 'library_notifier_base.dart';

/// 书架删除与清理 mixin
/// 负责移除书架项、删除本地文件、清理孤儿目录等销毁类操作
mixin LibraryDeleteMixin on LibraryNotifierBase
{
    /// 移除书架项
    Future<void> removeAlbum(String albumId) async
    {
        await libraryDao.removeAlbum(albumId);
        await loadLibrary();
    }

    /// 删除已下载漫画（含本地文件）
    /// 返回 true 表示本地文件被成功删除（如果不存在则视为成功）
    Future<bool> deleteAlbumWithFiles(String albumId) async
    {
        final album = state.albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return true;
        final downloadDir = await resolveDownloadDir();
        final ok = await LibraryStorage.deleteAlbumFiles(album, downloadDir: downloadDir);
        await libraryDao.removeAlbum(albumId);
        await loadLibrary();
        return ok;
    }

    /// 批量删除已下载漫画（同时删除本地文件）
    /// 返回 (总条目数, 失败数量)
    Future<(int total, int failed)> deleteAlbums(Iterable<String> albumIds) async
    {
        final idList = albumIds.toList();
        if (idList.isEmpty) return (0, 0);

        final downloadDir = await resolveDownloadDir();
        final targets = state.albums
            .where((a) => idList.contains(a.albumId))
            .toList();
        final results = await LibraryStorage.deleteBatchAlbumFiles(
            targets,
            downloadDir: downloadDir,
        );
        final failed = results.values.where((ok) => !ok).length;
        await libraryDao.removeAlbums(idList);
        await loadLibrary();
        return (idList.length, failed);
    }

    /// 清空整个书架（包含所有本地文件）
    /// 通常由用户二次确认后调用
    Future<int> clearAllWithFiles() async
    {
        final downloadDir = await resolveDownloadDir();
        final results = await LibraryStorage.deleteBatchAlbumFiles(
            state.albums,
            downloadDir: downloadDir,
        );
        final failed = results.values.where((ok) => !ok).length;
        await libraryDao.clearAll();
        await loadLibrary();
        return failed;
    }

    /// 清理下载目录中已不在书架的孤儿文件夹
    Future<int> cleanupOrphanFolders() async
    {
        final downloadDir = await resolveDownloadDir();
        final removed = await LibraryStorage.cleanupOrphans(
            state.albums,
            downloadDir: downloadDir,
        );
        return removed.length;
    }
}
