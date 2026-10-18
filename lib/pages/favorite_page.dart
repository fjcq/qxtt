import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/favorite_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/album_card.dart';
import '../widgets/error_widget.dart';
import '../widgets/shimmer_skeleton.dart';

/// 我的收藏页（需登录）
///
/// 网格展示账号收藏夹内容，支持下拉刷新与滚动加载更多；
/// 取消收藏后列表本地同步移除。
class FavoritePage extends ConsumerStatefulWidget
{
    const FavoritePage({super.key});

    @override
    ConsumerState<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends ConsumerState<FavoritePage>
{
    final _scrollController = ScrollController();

    @override
    void initState()
    {
        super.initState();
        _scrollController.addListener(_onScroll);
        // 首次进入自动加载（延迟一帧避免 build 期间修改 provider）
        Future.microtask(() =>
            ref.read(favoriteProvider.notifier).refresh());
    }

    @override
    void dispose()
    {
        _scrollController.removeListener(_onScroll);
        _scrollController.dispose();
        super.dispose();
    }

    /// 滚动接近底部时加载更多
    void _onScroll()
    {
        if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300)
        {
            ref.read(favoriteProvider.notifier).loadMore();
        }
    }

    @override
    Widget build(BuildContext context)
    {
        final favState = ref.watch(favoriteProvider);
        final authState = ref.watch(authProvider);

        return Scaffold(
            appBar: AppBar(title: Text('我的收藏 (${favState.total})')),
            body: _buildBody(context, favState, authState.loggedIn),
        );
    }

    /// 构建主体
    Widget _buildBody(BuildContext context, FavoriteState state, bool loggedIn)
    {
        // 未登录引导
        if (!loggedIn && state.items.isEmpty)
        {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.favorite_border,
                            size: 64,
                            color: context.appColors.textDisabled.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '登录后可同步查看收藏',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 16,
                            ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: context.appColors.accent,
                            ),
                            onPressed: () => context.push('/settings'),
                            child: const Text('去登录'),
                        ),
                    ],
                ),
            );
        }

        // 首屏加载骨架屏
        if (state.isLoading && state.items.isEmpty)
        {
            return const AlbumGridSkeleton();
        }

        // 首屏错误
        if (state.error != null && state.items.isEmpty)
        {
            return AppErrorWidget(
                message: state.error!,
                onRetry: () => ref.read(favoriteProvider.notifier).refresh(),
            );
        }

        // 空收藏
        if (state.items.isEmpty)
        {
            return Center(
                child: Text(
                    '暂无收藏，去详情页收藏喜欢的本子吧',
                    style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 14,
                    ),
                ),
            );
        }

        return RefreshIndicator(
            color: context.appColors.accent,
            onRefresh: () => ref.read(favoriteProvider.notifier).refresh(),
            child: GridView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.55,
                ),
                itemCount: state.items.length + (state.hasMore ? 1 : 0),
                itemBuilder: (context, index)
                {
                    // 尾部加载更多指示器
                    if (index >= state.items.length)
                    {
                        return const Center(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ),
                        );
                    }
                    final album = state.items[index];
                    return AlbumCard(
                        key: ValueKey(album.id),
                        album: album,
                        onTap: () => context.push('/album/${album.id}'),
                    );
                },
            ),
        );
    }
}
