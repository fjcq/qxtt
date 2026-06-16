import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import 'search_provider.dart';

/// 阅读器模式
enum ReaderMode
{
    /// 纵向滚动
    vertical,

    /// 横向翻页
    horizontal,

    /// Webtoon 长条滚动
    webtoon,
}

/// 阅读器状态
class ReaderState
{
    /// 章节 ID
    final String photoId;

    /// 图片 URL 列表
    final List<String> imageUrls;

    /// 当前页码
    final int currentPage;

    /// 阅读模式
    final ReaderMode mode;

    /// 是否正在加载
    final bool isLoading;

    /// 是否显示控制栏
    final bool showControls;

    /// 错误信息
    final String? error;

    /// scramble_id
    final int scrambleId;

    const ReaderState({
        required this.photoId,
        this.imageUrls = const [],
        this.currentPage = 0,
        this.mode = ReaderMode.vertical,
        this.isLoading = false,
        this.showControls = false,
        this.error,
        this.scrambleId = 0,
    });

    ReaderState copyWith({
        List<String>? imageUrls,
        int? currentPage,
        ReaderMode? mode,
        bool? isLoading,
        bool? showControls,
        String? error,
        int? scrambleId,
    })
    {
        return ReaderState(
            photoId: photoId,
            imageUrls: imageUrls ?? this.imageUrls,
            currentPage: currentPage ?? this.currentPage,
            mode: mode ?? this.mode,
            isLoading: isLoading ?? this.isLoading,
            showControls: showControls ?? this.showControls,
            error: error,
            scrambleId: scrambleId ?? this.scrambleId,
        );
    }

    /// 总页数
    int get totalPages => imageUrls.length;
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

            // 构造图片 URL 列表
            final urls = photoDetail.pageArr.map((filename)
            {
                return _client.getImageUrl(state.photoId, filename);
            }).toList();

            state = state.copyWith(
                imageUrls: urls,
                scrambleId: scrambleId,
                isLoading: false,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
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

    /// 切换阅读模式
    void toggleMode()
    {
        final modes = ReaderMode.values;
        final currentIndex = modes.indexOf(state.mode);
        final nextIndex = (currentIndex + 1) % modes.length;
        state = state.copyWith(mode: modes[nextIndex]);
    }

    /// 设置阅读模式
    void setMode(ReaderMode mode)
    {
        state = state.copyWith(mode: mode);
    }

    /// 切换控制栏显示
    void toggleControls()
    {
        state = state.copyWith(showControls: !state.showControls);
    }
}

/// 阅读器 Provider 工厂
final readerProvider = StateNotifierProvider.family<ReaderNotifier, ReaderState, String>((ref, photoId)
{
    final client = ref.watch(jmClientProvider);
    return ReaderNotifier(client, photoId);
});
