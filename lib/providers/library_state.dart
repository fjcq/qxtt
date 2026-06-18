import '../data/models/library_album_model.dart';
import 'library_sort_type.dart';

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
