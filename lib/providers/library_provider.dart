import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/library_dao.dart';
import '../data/models/library_album_model.dart';
import '../utils/cover_refresher.dart';
import '../utils/library_storage.dart';
import 'config_provider.dart';
import 'search_provider.dart';

/// 书架排序方式
enum LibrarySortType
{
    /// 最近添加
    addedAtDesc,

    /// 最近阅读
    lastReadDesc,

    /// 标题 A→Z
    titleAsc,

    /// 占用空间 大→小
    sizeDesc,
}

/// 书架排序方式扩展
extension LibrarySortTypeX on LibrarySortType
{
    /// 列表中的展示标题
    String get label
    {
        switch (this)
        {
            case LibrarySortType.addedAtDesc:
                return '最近添加';
            case LibrarySortType.lastReadDesc:
                return '最近阅读';
            case LibrarySortType.titleAsc:
                return '标题';
            case LibrarySortType.sizeDesc:
                return '占用空间';
        }
    }
}

/// 书架状态
class LibraryState
{
    /// 书架列表
    final List<LibraryAlbumModel> albums;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    /// 排序方式
    final LibrarySortType sortType;

    /// 搜索关键字（标题/作者）
    final String keyword;

    const LibraryState({
        this.albums = const [],
        this.isLoading = false,
        this.error,
        this.sortType = LibrarySortType.addedAtDesc,
        this.keyword = '',
    });

    /// 过滤并排序后的视图
    List<LibraryAlbumModel> get visibleAlbums
    {
        var list = albums;
        if (keyword.trim().isNotEmpty)
        {
            final kw = keyword.trim().toLowerCase();
            list = list
                .where((a) =>
                    a.title.toLowerCase().contains(kw) ||
                    a.author.toLowerCase().contains(kw))
                .toList();
        }
        final sorted = List<LibraryAlbumModel>.from(list);
        switch (sortType)
        {
            case LibrarySortType.addedAtDesc:
                sorted.sort(
                    (a, b) => (b.addedAt).compareTo(a.addedAt),
                );
                break;
            case LibrarySortType.lastReadDesc:
                sorted.sort((a, b)
                {
                    final av = a.lastReadAt ?? '';
                    final bv = b.lastReadAt ?? '';
                    // 未阅读的排到末尾
                    if (av.isEmpty && bv.isEmpty) return 0;
                    if (av.isEmpty) return 1;
                    if (bv.isEmpty) return -1;
                    return bv.compareTo(av);
                });
                break;
            case LibrarySortType.titleAsc:
                sorted.sort(
                    (a, b) => a.title.compareTo(b.title),
                );
                break;
            case LibrarySortType.sizeDesc:
                sorted.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
                break;
        }
        return sorted;
    }

    /// 总占用字节数
    int get totalSizeBytes
    {
        var total = 0;
        for (final album in albums)
        {
            total += album.sizeBytes;
        }
        return total;
    }

    /// 总文件数
    int get totalFileCount
    {
        var total = 0;
        for (final album in albums)
        {
            total += album.fileCount;
        }
        return total;
    }

    /// 总章节数（已下载）
    int get totalDownloadedEpisodes
    {
        var total = 0;
        for (final album in albums)
        {
            total += album.downloadedEpisodes.length;
        }
        return total;
    }

    LibraryState copyWith({
        List<LibraryAlbumModel>? albums,
        bool? isLoading,
        String? error,
        LibrarySortType? sortType,
        String? keyword,
    })
    {
        return LibraryState(
            albums: albums ?? this.albums,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            sortType: sortType ?? this.sortType,
            keyword: keyword ?? this.keyword,
        );
    }
}

/// 书架 Provider
class LibraryNotifier extends StateNotifier<LibraryState>
{
    final LibraryDao _libraryDao;
    final Ref _ref;

    LibraryNotifier(this._libraryDao, this._ref) : super(const LibraryState());

    /// 解析下载目录
    /// 1) 等待 ConfigNotifier 完成初始化（避免首帧拿到空 downloadDir）
    /// 2) 优先使用 ConfigNotifier 里的 downloadDir（用户实际配置）
    /// 3) 为空时回退到默认下载目录
    Future<String> _resolveDownloadDir() async
    {
        await _ref.read(configProvider.notifier).initialized;
        final configured = _ref.read(configProvider).config.downloadDir;
        return LibraryStorage.getDownloadDir(configured: configured);
    }

    /// 加载书架
    Future<void> loadLibrary() async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final albums = await _libraryDao.getAllAlbums();
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
            await _libraryDao.syncFromDirectory(downloadDir);
            final albums = await _libraryDao.getAllAlbums();
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
            final downloadDir = await _resolveDownloadDir();
            final statsMap = await LibraryStorage.computeBatchDiskUsage(
                state.albums,
                downloadDir: downloadDir,
            );
            // 写回 DAO 持久化
            final persistMap = <String, AlbumSizeStats>{};
            statsMap.forEach((id, stats) {
                persistMap[id] =
                    AlbumSizeStats(sizeBytes: stats.sizeBytes, fileCount: stats.fileCount);
            });
            await _libraryDao.updateAlbumsSize(persistMap);
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
            await _libraryDao.updateAlbumSize(
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

    /// 移除书架项
    Future<void> removeAlbum(String albumId) async
    {
        await _libraryDao.removeAlbum(albumId);
        await loadLibrary();
    }

    /// 删除已下载漫画（含本地文件）
    /// 返回 true 表示本地文件被成功删除（如果不存在则视为成功）
    Future<bool> deleteAlbumWithFiles(String albumId) async
    {
        final album = state.albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return true;
        final downloadDir = await _resolveDownloadDir();
        final ok = await LibraryStorage.deleteAlbumFiles(album, downloadDir: downloadDir);
        await _libraryDao.removeAlbum(albumId);
        await loadLibrary();
        return ok;
    }

    /// 批量删除已下载漫画（同时删除本地文件）
    /// 返回 (总条目数, 失败数量)
    Future<(int total, int failed)> deleteAlbums(Iterable<String> albumIds) async
    {
        final idList = albumIds.toList();
        if (idList.isEmpty) return (0, 0);

        final downloadDir = await _resolveDownloadDir();
        final targets = state.albums
            .where((a) => idList.contains(a.albumId))
            .toList();
        final results = await LibraryStorage.deleteBatchAlbumFiles(
            targets,
            downloadDir: downloadDir,
        );
        final failed = results.values.where((ok) => !ok).length;
        await _libraryDao.removeAlbums(idList);
        await loadLibrary();
        return (idList.length, failed);
    }

    /// 清空整个书架（包含所有本地文件）
    /// 通常由用户二次确认后调用
    Future<int> clearAllWithFiles() async
    {
        final downloadDir = await _resolveDownloadDir();
        final results = await LibraryStorage.deleteBatchAlbumFiles(
            state.albums,
            downloadDir: downloadDir,
        );
        final failed = results.values.where((ok) => !ok).length;
        await _libraryDao.clearAll();
        await loadLibrary();
        return failed;
    }

    /// 清理下载目录中已不在书架的孤儿文件夹
    Future<int> cleanupOrphanFolders() async
    {
        final downloadDir = await _resolveDownloadDir();
        final removed = await LibraryStorage.cleanupOrphans(
            state.albums,
            downloadDir: downloadDir,
        );
        return removed.length;
    }

    /// 更新阅读进度
    Future<void> updateReadProgress(String albumId, int page) async
    {
        await _libraryDao.updateReadProgress(albumId, page);
    }

    /// 标记章节已下载并刷新书架
    /// 当 coverPath 缺失或对应文件不存在时，自动用 localPath 下首张已下载图补封面
    Future<void> markEpisodesDownloaded(
        String albumId,
        Iterable<String> photoIds, {
        String? title,
        String? author,
        String? coverPath,
        String? localPath,
        int? pageCount,
        int? episodeCount,
    }) async
    {
        // 1) 优先使用调用方提供的 coverPath
        var resolvedCover = coverPath ?? '';

        // 2) coverPath 为空或对应文件不存在 → 尝试用本子目录下首张已下载图补封面
        final coverValid = resolvedCover.isNotEmpty &&
            await File(resolvedCover).exists();
        if (!coverValid && (localPath?.isNotEmpty ?? false))
        {
            final firstImg = await _findFirstImage(localPath!);
            if (firstImg != null) resolvedCover = firstImg;
        }
        else if (!coverValid &&
            (title?.isNotEmpty ?? false) &&
            localPath == null)
        {
            // 兜底：localPath 为空时按 title 拼目录再找首张
            final downloadDir = await _resolveDownloadDir();
            final temp = LibraryAlbumModel()
                ..albumId = albumId
                ..title = title!;
            final dir = await LibraryStorage.resolveAlbumDir(
                temp,
                downloadDir: downloadDir,
            );
            final firstImg = await _findFirstImage(dir);
            if (firstImg != null) resolvedCover = firstImg;
        }

        await _libraryDao.markEpisodesDownloaded(
            albumId,
            photoIds,
            title: title,
            author: author,
            coverPath: resolvedCover.isEmpty ? null : resolvedCover,
            localPath: localPath,
            pageCount: pageCount,
            episodeCount: episodeCount,
        );
        await loadLibrary();
    }

    /// 在 albumDir 下递归查找第一张可用图片
    /// 用于在没有 cover.jpg 的旧本子上兜底显示首张图
    Future<String?> _findFirstImage(String albumDir) async
    {
        try
        {
            final dir = Directory(albumDir);
            if (!await dir.exists()) return null;
            final entries = await dir.list(recursive: true).toList();
            final images = entries
                .whereType<File>()
                .where((f) =>
                    f.path.toLowerCase().endsWith('.jpg') ||
                    f.path.toLowerCase().endsWith('.jpeg') ||
                    f.path.toLowerCase().endsWith('.webp') ||
                    f.path.toLowerCase().endsWith('.png'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
            return images.isEmpty ? null : images.first.path;
        }
        catch (_)
        {
            return null;
        }
    }

    /// 移除指定章节的已下载标记
    Future<void> removeDownloadedEpisodes(String albumId, Iterable<String> photoIds) async
    {
        await _libraryDao.removeDownloadedEpisodes(albumId, photoIds);
        await loadLibrary();
    }

    /// 为单个本子补封面
    /// - 已有 cover 且文件存在 → 跳过
    /// - 本地有 cover.jpg → 直接回填
    /// - 远端拉取 → 保存到 <albumDir>/cover.jpg
    /// - 全失败 → 用本子首张已下载图兜底
    /// 完成后写回 DAO 并刷新 state
    Future<String> refreshCover(LibraryAlbumModel album) async
    {
        // 已有 cover 且文件存在
        if (album.coverPath.isNotEmpty && await File(album.coverPath).exists())
        {
            return album.coverPath;
        }

        // 解析本子目录
        final downloadDir = await _resolveDownloadDir();
        final albumDir = await LibraryStorage.resolveAlbumDir(
            album,
            downloadDir: downloadDir,
        );
        final dirExists = await Directory(albumDir).exists();
        if (!dirExists) return '';

        // 本地已有 cover.jpg
        final localCover = File('$albumDir${Platform.pathSeparator}cover.jpg');
        if (await localCover.exists())
        {
            await _libraryDao.updateAlbumCover(album.albumId, localCover.path);
            await loadLibrary();
            return localCover.path;
        }

        // 远端拉取
        final refresher = CoverRefresher(_ref.read(jmClientProvider));
        final resolved = await refresher.refresh(album);
        if (resolved.isNotEmpty)
        {
            await _libraryDao.updateAlbumCover(album.albumId, resolved);
            await loadLibrary();
        }
        return resolved;
    }

    /// 获取指定本子已下载章节 ID 集合
    Future<Set<String>> getDownloadedEpisodes(String albumId) async
    {
        return _libraryDao.getDownloadedEpisodes(albumId);
    }

    /// 设置排序方式
    void setSortType(LibrarySortType sortType)
    {
        state = state.copyWith(sortType: sortType);
    }

    /// 设置搜索关键字
    void setKeyword(String keyword)
    {
        state = state.copyWith(keyword: keyword);
    }
}

/// 书架 Provider 实例
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref)
{
    final libraryDao = ref.watch(libraryDaoProvider);
    return LibraryNotifier(libraryDao, ref);
});

/// 获取本子已下载章节 ID 集合的辅助 Provider
/// 使用 family 以便按 albumId 缓存不同本子的已下载状态
final downloadedEpisodesProvider = Provider.family<Set<String>, String>((ref, albumId)
{
    final albums = ref.watch(libraryProvider).albums;
    final album = albums.where((a) => a.albumId == albumId).firstOrNull;
    if (album == null) return <String>{};
    return album.downloadedEpisodes.toSet();
});

/// 获取下载根目录（与 ConfigNotifier 默认值保持一致）
final downloadDirProvider = Provider<String>((ref)
{
    final configured = ref.watch(configProvider).config.downloadDir;
    if (configured.isNotEmpty) return configured;
    // 默认值会在 ConfigNotifier 初始化时填充；此处仅兜底
    return '';
});
