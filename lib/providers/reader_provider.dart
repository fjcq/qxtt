import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import 'search_provider.dart';

/// 阅读器状态
class ReaderState
{
    /// 章节 ID
    final String photoId;

    /// 图片 URL 列表
    final List<String> imageUrls;

    /// 当前页码
    final int currentPage;

    /// 是否正在加载
    final bool isLoading;

    /// 是否显示控制栏
    final bool showControls;

    /// 错误信息
    final String? error;

    /// scramble_id
    final int scrambleId;

    /// 本子详情（用于章节导航）
    final AlbumDetail? albumDetail;

    /// 当前章节名称
    final String chapterName;

    /// 是否正在切换章节（显示章节切换加载状态）
    final bool isChapterLoading;

    const ReaderState({
        required this.photoId,
        this.imageUrls = const [],
        this.currentPage = 0,
        this.isLoading = false,
        this.showControls = false,
        this.error,
        this.scrambleId = 0,
        this.albumDetail,
        this.chapterName = '',
        this.isChapterLoading = false,
    });

    ReaderState copyWith({
        String? photoId,
        List<String>? imageUrls,
        int? currentPage,
        bool? isLoading,
        bool? showControls,
        String? error,
        int? scrambleId,
        AlbumDetail? albumDetail,
        String? chapterName,
        bool? isChapterLoading,
    })
    {
        return ReaderState(
            photoId: photoId ?? this.photoId,
            imageUrls: imageUrls ?? this.imageUrls,
            currentPage: currentPage ?? this.currentPage,
            isLoading: isLoading ?? this.isLoading,
            showControls: showControls ?? this.showControls,
            error: error,
            scrambleId: scrambleId ?? this.scrambleId,
            albumDetail: albumDetail ?? this.albumDetail,
            chapterName: chapterName ?? this.chapterName,
            isChapterLoading: isChapterLoading ?? this.isChapterLoading,
        );
    }

    /// 总页数
    int get totalPages => imageUrls.length;

    /// 当前章节在列表中的索引
    int get currentEpisodeIndex
    {
        if (albumDetail == null) return -1;
        for (var i = 0; i < albumDetail!.episodes.length; i++)
        {
            if (albumDetail!.episodes[i].photoId == photoId)
            {
                return i;
            }
        }
        return -1;
    }

    /// 是否有上一章
    bool get hasPrevChapter
    {
        final idx = currentEpisodeIndex;
        return idx > 0;
    }

    /// 是否有下一章
    bool get hasNextChapter
    {
        final idx = currentEpisodeIndex;
        return idx >= 0 && idx < (albumDetail?.episodes.length ?? 0) - 1;
    }

    /// 章节列表
    List<Episode> get episodes => albumDetail?.episodes ?? const [];
}

/// 阅读器 Provider
class ReaderNotifier extends StateNotifier<ReaderState>
{
    final JmClient _client;

    ReaderNotifier(this._client, String photoId)
        : super(ReaderState(photoId: photoId));

    /// 加载章节图片列表
    Future<void> loadPages() async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final photoDetail = await _client.getPhotoDetail(state.photoId);
            final scrambleId = await _client.getScrambleId(state.photoId);

            // 尝试获取本子详情（用于章节导航）
            AlbumDetail? albumDetail;
            try
            {
                albumDetail = await _client.getAlbumDetail(photoDetail.albumId);
            }
            catch (_)
            {
                albumDetail = null;
            }

            // 构造图片 URL 列表
            final urls = photoDetail.pageArr.map((filename)
            {
                return _client.getImageUrl(state.photoId, filename);
            }).toList();

            // 查找当前章节名称
            String chapterName = '';
            if (albumDetail != null)
            {
                for (final ep in albumDetail.episodes)
                {
                    if (ep.photoId == state.photoId)
                    {
                        chapterName = ep.name;
                        break;
                    }
                }
            }

            state = state.copyWith(
                imageUrls: urls,
                scrambleId: scrambleId,
                isLoading: false,
                albumDetail: albumDetail,
                chapterName: chapterName,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 切换到指定章节
    Future<void> switchChapter(String photoId) async
    {
        state = state.copyWith(
            isChapterLoading: true,
            error: null,
            photoId: photoId,
            currentPage: 0,
        );

        try
        {
            final photoDetail = await _client.getPhotoDetail(photoId);
            final scrambleId = await _client.getScrambleId(photoId);

            // 如果尚未获取本子详情，尝试获取
            if (state.albumDetail == null)
            {
                try
                {
                    final albumDetail = await _client.getAlbumDetail(
                        photoDetail.albumId,
                    );
                    state = state.copyWith(albumDetail: albumDetail);
                }
                catch (_)
                {
                    // 忽略
                }
            }

            // 构造图片 URL 列表
            final urls = photoDetail.pageArr.map((filename)
            {
                return _client.getImageUrl(photoId, filename);
            }).toList();

            // 查找章节名称
            String chapterName = '';
            if (state.albumDetail != null)
            {
                for (final ep in state.albumDetail!.episodes)
                {
                    if (ep.photoId == photoId)
                    {
                        chapterName = ep.name;
                        break;
                    }
                }
            }

            state = state.copyWith(
                imageUrls: urls,
                scrambleId: scrambleId,
                isChapterLoading: false,
                chapterName: chapterName,
            );
        }
        catch (e)
        {
            state = state.copyWith(
                isChapterLoading: false,
                error: e.toString(),
            );
        }
    }

    /// 切换页码
    void setCurrentPage(int page)
    {
        if (page >= 0 && page < state.totalPages)
        {
            state = state.copyWith(currentPage: page);
        }
    }

    /// 下一页
    void nextPage()
    {
        if (state.currentPage < state.totalPages - 1)
        {
            state = state.copyWith(currentPage: state.currentPage + 1);
        }
    }

    /// 上一页
    void prevPage()
    {
        if (state.currentPage > 0)
        {
            state = state.copyWith(currentPage: state.currentPage - 1);
        }
    }

    /// 切换控制栏显示
    void toggleControls()
    {
        state = state.copyWith(showControls: !state.showControls);
    }

    /// 跳转上一章
    void goToPrevChapter()
    {
        final idx = state.currentEpisodeIndex;
        if (idx > 0 && state.albumDetail != null)
        {
            final prevPhotoId = state.albumDetail!.episodes[idx - 1].photoId;
            switchChapter(prevPhotoId);
        }
    }

    /// 跳转下一章
    void goToNextChapter()
    {
        final idx = state.currentEpisodeIndex;
        if (idx >= 0 && state.albumDetail != null &&
            idx < state.albumDetail!.episodes.length - 1)
        {
            final nextPhotoId = state.albumDetail!.episodes[idx + 1].photoId;
            switchChapter(nextPhotoId);
        }
    }
}

/// 阅读器 Provider 工厂
final readerProvider = StateNotifierProvider.family<ReaderNotifier, ReaderState, String>((ref, photoId)
{
    final client = ref.watch(jmClientProvider);
    return ReaderNotifier(client, photoId);
});
