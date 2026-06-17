import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/album_card.dart';
import '../widgets/category_chip.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';

/// 分类列表定义
class _CategoryDef
{
    final String value;
    final String label;
    const _CategoryDef(this.value, this.label);
}

/// 时间列表定义
class _TimeDef
{
    final String value;
    final String label;
    const _TimeDef(this.value, this.label);
}

/// 分类浏览页
class CategoryPage extends ConsumerStatefulWidget
{
    const CategoryPage({super.key});

    @override
    ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage>
{
    static const _categories = [
        _CategoryDef('0', '全部'),
        _CategoryDef('doujin', '同人'),
        _CategoryDef('single', '单本'),
        _CategoryDef('short', '短篇'),
        _CategoryDef('hanman', '韩漫'),
        _CategoryDef('meiman', '美漫'),
        _CategoryDef('another', '其他'),
        _CategoryDef('3D', '3D'),
    ];

    static const _times = [
        _TimeDef('a', '全部'),
        _TimeDef('t', '今日'),
        _TimeDef('w', '本周'),
        _TimeDef('m', '本月'),
    ];

    String _selectedCategory = '0';
    String _selectedTime = 'a';

    @override
    void initState()
    {
        super.initState();
        // 首次加载
        Future.microtask(() =>
            ref.read(categoryProvider.notifier).loadCategory(
                category: _selectedCategory,
                time: _selectedTime,
            ),
        );
    }

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(categoryProvider);

        return Scaffold(
            appBar: AppBar(title: const Text('分类浏览')),
            body: Column(
                children: [
                    // 分类选择
                    _buildCategoryChips(),
                    const SizedBox(height: 8),
                    // 时间选择
                    _buildTimeChips(),
                    const Divider(color: AppColors.divider),
                    // 结果列表
                    Expanded(child: _buildResults(state)),
                ],
            ),
        );
    }

    /// 构建分类标签
    Widget _buildCategoryChips()
    {
        return SizedBox(
            height: 44,
            child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index)
                {
                    final cat = _categories[index];
                    return CategoryChip(
                        label: cat.label,
                        isSelected: _selectedCategory == cat.value,
                        onTap: ()
                        {
                            setState(() => _selectedCategory = cat.value);
                            ref.read(categoryProvider.notifier).loadCategory(
                                category: _selectedCategory,
                                time: _selectedTime,
                            );
                        },
                    );
                },
            ),
        );
    }

    /// 构建时间标签
    Widget _buildTimeChips()
    {
        return SizedBox(
            height: 40,
            child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _times.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index)
                {
                    final time = _times[index];
                    return CategoryChip(
                        label: time.label,
                        isSelected: _selectedTime == time.value,
                        onTap: ()
                        {
                            setState(() => _selectedTime = time.value);
                            ref.read(categoryProvider.notifier).loadCategory(
                                category: _selectedCategory,
                                time: _selectedTime,
                            );
                        },
                    );
                },
            ),
        );
    }

    /// 构建结果列表
    Widget _buildResults(CategoryState state)
    {
        if (state.isLoading && state.results.isEmpty)
        {
            return const LoadingWidget(message: '加载中...');
        }

        if (state.error != null && state.results.isEmpty)
        {
            return AppErrorWidget(
                message: state.error!,
                onRetry: () => ref.read(categoryProvider.notifier).loadCategory(
                    category: _selectedCategory,
                    time: _selectedTime,
                ),
            );
        }

        if (state.results.isEmpty)
        {
            return const Center(
                child: Text(
                    '暂无数据',
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
                    ref.read(categoryProvider.notifier).loadMore();
                }
                return false;
            },
            child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.55,
                ),
                itemCount: state.results.length,
                itemBuilder: (context, index)
                {
                    final album = state.results[index];
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
