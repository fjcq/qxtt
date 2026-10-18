import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import 'auth_provider.dart';
import 'search_provider.dart';

/// 收藏列表状态
class FavoriteState
{
    /// 收藏列表
    final List<SearchItem> items;

    /// 是否正在加载（首次/刷新）
    final bool isLoading;

    /// 是否正在加载更多
    final bool isLoadingMore;

    /// 错误信息
    final String? error;

    /// 当前页码
    final int currentPage;

    /// 收藏总数
    final int total;

    /// 是否还有更多页
    final bool hasMore;

    const FavoriteState({
        this.items = const [],
        this.isLoading = false,
        this.isLoadingMore = false,
        this.error,
        this.currentPage = 0,
        this.total = 0,
        this.hasMore = true,
    });

    FavoriteState copyWith({
        List<SearchItem>? items,
        bool? isLoading,
        bool? isLoadingMore,
        String? error,
        bool clearError = false,
        int? currentPage,
        int? total,
        bool? hasMore,
    })
    {
        return FavoriteState(
            items: items ?? this.items,
            isLoading: isLoading ?? this.isLoading,
            isLoadingMore: isLoadingMore ?? this.isLoadingMore,
            error: clearError ? null : (error ?? this.error),
            currentPage: currentPage ?? this.currentPage,
            total: total ?? this.total,
            hasMore: hasMore ?? this.hasMore,
        );
    }
}

/// 收藏列表 Provider
///
/// 需登录后使用：未登录时 [refresh] 会把错误写入 state.error。
class FavoriteNotifier extends StateNotifier<FavoriteState>
{
    final JmClient _client;
    final Ref _ref;

    FavoriteNotifier(this._client, this._ref) : super(const FavoriteState());

    /// 刷新收藏列表（下拉刷新 / 首次加载）
    Future<void> refresh() async
    {
        if (state.isLoading) return;
        state = state.copyWith(isLoading: true, clearError: true);

        try
        {
            final result = await _client.favorites(page: 1);
            final hasMore = result.total > result.results.length;
            state = FavoriteState(
                items: result.results,
                isLoading: false,
                currentPage: 1,
                total: result.total,
                hasMore: hasMore,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 加载下一页
    Future<void> loadMore() async
    {
        if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
        state = state.copyWith(isLoadingMore: true, clearError: true);

        try
        {
            final nextPage = state.currentPage + 1;
            final result = await _client.favorites(page: nextPage);
            final items = [...state.items, ...result.results];
            // 无新增数据说明已到末页
            final hasMore = result.results.isNotEmpty && items.length < result.total;
            state = state.copyWith(
                items: items,
                isLoadingMore: false,
                currentPage: nextPage,
                total: result.total,
                hasMore: hasMore,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoadingMore: false, error: e.toString());
        }
    }

    /// 切换指定本子的收藏状态（收藏/取消收藏）
    ///
    /// 返回实际操作类型：add=已收藏 / remove=已取消；失败抛异常由调用方处理。
    Future<String> toggle(String albumId) async
    {
        final result = await _client.toggleFavorite(albumId);
        // 本地同步：从列表移除被取消收藏的本子，并更新账号收藏数
        if (result.type == 'remove')
        {
            state = state.copyWith(
                items: state.items.where((e) => e.id != albumId).toList(),
                total: (state.total - 1).clamp(0, 1 << 31),
            );
        }
        final auth = _ref.read(authProvider.notifier);
        final count = result.type == 'add'
            ? auth.state.albumFavorites + 1
            : (auth.state.albumFavorites - 1).clamp(0, 1 << 31);
        auth.updateAlbumFavorites(count);
        return result.type;
    }
}

/// 收藏列表 Provider 实例
final favoriteProvider = StateNotifierProvider<FavoriteNotifier, FavoriteState>((ref)
{
    final client = ref.watch(jmClientProvider);
    return FavoriteNotifier(client, ref);
});
