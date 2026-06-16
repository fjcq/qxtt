import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/library_dao.dart';
import '../data/models/library_album_model.dart';
import 'search_provider.dart';

/// 书架状态
class LibraryState
{
    /// 书架列表
    final List<LibraryAlbumModel> albums;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    const LibraryState({
        this.albums = const [],
        this.isLoading = false,
        this.error,
    });

    LibraryState copyWith({
        List<LibraryAlbumModel>? albums,
        bool? isLoading,
        String? error,
    })
    {
        return LibraryState(
            albums: albums ?? this.albums,
            isLoading: isLoading ?? this.isLoading,
            error: error,
        );
    }
}

/// 书架 Provider
class LibraryNotifier extends StateNotifier<LibraryState>
{
    final LibraryDao _libraryDao;

    LibraryNotifier(this._libraryDao) : super(const LibraryState());

    /// 加载书架
    Future<void> loadLibrary() async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final albums = await _libraryDao.getAllAlbums();
            state = state.copyWith(albums: albums, isLoading: false);
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
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 移除书架项
    Future<void> removeAlbum(String albumId) async
    {
        await _libraryDao.removeAlbum(albumId);
        await loadLibrary();
    }

    /// 更新阅读进度
    Future<void> updateReadProgress(String albumId, int page) async
    {
        await _libraryDao.updateReadProgress(albumId, page);
    }
}

/// 书架 Provider 实例
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref)
{
    final libraryDao = ref.watch(libraryDaoProvider);
    return LibraryNotifier(libraryDao);
});
