import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/album_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';

/// 搜索结果页
class SearchPage extends ConsumerWidget
{
    const SearchPage({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final state = ref.watch(searchProvider);

        return Scaffold(
            appBar: AppBar(
                title: Text(state.query),
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                ),
            ),
            body: _buildBody(context, ref, state),
        );
    }

    /// 构建主体
    Widget _buildBody(BuildContext context, WidgetRef ref, SearchState state)
    {
        if (state.isLoading && state.results.isEmpty)
        {
            return const LoadingWidget(message: '搜索中...');
        }

        if (state.error != null && state.results.isEmpty)
        {
            return AppErrorWidget(
                message: state.error!,
                onRetry: () => ref.read(searchProvider.notifier).search(state.query),
            );
        }

        if (state.results.isEmpty)
        {
            return const Center(
                child: Text(
                    '没有找到结果',
                    style: TextStyle(color: AppColors.textSecondary),
                ),
            );
        }

        return NotificationListener<ScrollNotification>(
            onNotification: (notification)
            {
                if (notification is ScrollEndNotification &&
                    notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent * 0.8)
                {
                    ref.read(searchProvider.notifier).loadMore();
                }
                return false;
            },
            child: CustomScrollView(
                slivers: [
                    SliverPadding(
                        padding: const EdgeInsets.all(8),
                        sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.55,
                            ),
                            delegate: SliverChildBuilderDelegate(
                                (context, index)
                                {
                                    final album = state.results[index];
                                    return AlbumCard(
                                        album: album,
                                        onTap: () => context.push('/album/${album.id}'),
                                    );
                                },
                                childCount: state.results.length,
                            ),
                        ),
                    ),
                    // 加载更多指示器
                    if (state.isLoading)
                        const SliverToBoxAdapter(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.accent,
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    // 页码信息
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                                child: Text(
                                    '第 ${state.currentPage} / ${state.totalPages} 页  共 ${state.total} 条',
                                    style: const TextStyle(
                                        color: AppColors.textDisabled,
                                        fontSize: 12,
                                    ),
                                ),
                            ),
                        ),
                    ),
                ],
            ),
        );
    }
}
