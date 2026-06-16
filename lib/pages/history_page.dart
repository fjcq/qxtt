import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/browse_history_provider.dart';
import '../data/database/browse_history_dao.dart';
import '../theme/app_colors.dart';
import '../widgets/loading_widget.dart';

/// 浏览历史页
class HistoryPage extends ConsumerStatefulWidget
{
    const HistoryPage({super.key});

    @override
    ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage>
{
    @override
    void initState()
    {
        super.initState();
        Future.microtask(() => ref.read(browseHistoryProvider.notifier).loadHistory());
    }

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(browseHistoryProvider);

        return Scaffold(
            appBar: AppBar(
                title: const Text('历史'),
                actions: [
                    if (state.history.isNotEmpty)
                        IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _confirmClearAll,
                        ),
                ],
            ),
            body: _buildBody(state),
        );
    }

    /// 构建主体
    Widget _buildBody(BrowseHistoryState state)
    {
        if (state.isLoading && state.history.isEmpty)
        {
            return const LoadingWidget(message: '加载中...');
        }

        if (state.history.isEmpty)
        {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.history,
                            size: 64,
                            color: AppColors.textDisabled.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                            '暂无浏览记录',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                            ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            '浏览漫画后会自动记录',
                            style: TextStyle(
                                color: AppColors.textDisabled,
                                fontSize: 13,
                            ),
                        ),
                    ],
                ),
            );
        }

        return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.history.length,
            itemBuilder: (context, index)
            {
                return _buildHistoryItem(state.history[index]);
            },
        );
    }

    /// 构建历史项
    Widget _buildHistoryItem(BrowseHistoryModel item)
    {
        return Dismissible(
            key: Key(item.albumId),
            direction: DismissDirection.endToStart,
            background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: AppColors.error,
                child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) =>
                ref.read(browseHistoryProvider.notifier).deleteHistory(item.albumId),
            child: ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                        width: 56,
                        height: 76,
                        child: item.coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.coverUrl,
                                httpHeaders: const {'Referer': 'https://jmcomic1.bet'},
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(
                                        Icons.image_outlined,
                                        color: AppColors.textDisabled,
                                        size: 20,
                                    ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(
                                        Icons.broken_image,
                                        color: AppColors.textDisabled,
                                        size: 20,
                                    ),
                                ),
                            )
                            : Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(
                                    Icons.image_outlined,
                                    color: AppColors.textDisabled,
                                    size: 20,
                                ),
                            ),
                    ),
                ),
                title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                    ),
                ),
                subtitle: Text(
                    item.author.isNotEmpty ? item.author : _formatTime(item.browsedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                    ),
                ),
                trailing: Text(
                    _formatTime(item.browsedAt),
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                    ),
                ),
                onTap: () => context.push('/album/${item.albumId}'),
            ),
        );
    }

    /// 格式化时间
    String _formatTime(String isoTime)
    {
        try
        {
            final dt = DateTime.parse(isoTime);
            final now = DateTime.now();
            final diff = now.difference(dt);

            if (diff.inMinutes < 1) return '刚刚';
            if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
            if (diff.inDays < 1) return '${diff.inHours}小时前';
            if (diff.inDays < 7) return '${diff.inDays}天前';
            return '${dt.month}/${dt.day}';
        }
        catch (_)
        {
            return '';
        }
    }

    /// 确认清空所有历史
    void _confirmClearAll()
    {
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('清空历史'),
                content: const Text('确定要清空所有浏览记录吗？此操作不可恢复。'),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                    ),
                    TextButton(
                        onPressed: ()
                        {
                            Navigator.pop(context);
                            ref.read(browseHistoryProvider.notifier).clearAllHistory();
                        },
                        child: const Text('清空', style: TextStyle(color: AppColors.error)),
                    ),
                ],
            ),
        );
    }
}
