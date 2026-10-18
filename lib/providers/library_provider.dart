import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_provider.dart';
import 'library_delete_mixin.dart';
import 'library_notifier_base.dart';
import 'library_read_mixin.dart';
import 'library_sort_type.dart';
import 'library_state.dart';
import 'library_write_mixin.dart';
import 'search_provider.dart';

export 'library_delete_mixin.dart';
export 'library_notifier_base.dart';
export 'library_read_mixin.dart';
export 'library_sort_type.dart';
export 'library_state.dart';
export 'library_write_mixin.dart';

/// 书架 Provider
class LibraryNotifier extends LibraryNotifierBase
    with LibraryReadMixin, LibraryWriteMixin, LibraryDeleteMixin
{
    /// 构造书架 Provider
    LibraryNotifier(super.libraryDao, super.ref);

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

/// 全局已下载章节 photoId 扁平集合（跨本子）
///
/// photoId 全局唯一，直接扁平展开即可。
/// 供历史页等没有 albumId 上下文的入口判断"该章节是否已下载"，
/// 以决定跳转本地阅读器还是在线阅读器。
final downloadedPhotoIdIndexProvider = Provider<Set<String>>((ref)
{
    final albums = ref.watch(libraryProvider).albums;
    return albums.expand((a) => a.downloadedEpisodes).toSet();
});

/// 获取下载根目录（与 ConfigNotifier 默认值保持一致）
final downloadDirProvider = Provider<String>((ref)
{
    final configured = ref.watch(configProvider).config.downloadDir;
    if (configured.isNotEmpty) return configured;
    // 默认值会在 ConfigNotifier 初始化时填充；此处仅兜底
    return '';
});
