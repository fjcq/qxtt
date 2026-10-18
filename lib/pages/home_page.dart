import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/category_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/album_card.dart';
import '../widgets/category_chip.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/error_widget.dart';

/// 分类列表定义
class _CategoryDef
{
    final String value;
    final String label;
    const _CategoryDef(this.value, this.label);
}

/// 排序 Tab 定义：映射到 categories/filter 接口的 o 参数（orderBy + time）
class _SortTabDef
{
    final String label;

    /// 排序方式：'mr'=最新上架，'mv'=按观看数（最热）
    final String orderBy;

    /// 时间范围：'a'=全部，'t'=今日，'w'=本周，'m'=本月
    final String time;

    const _SortTabDef(this.label, this.orderBy, this.time);
}

/// 首页（分类浏览）
/// 顶部为排序 Tab（最新/今日最热/本周最热/本月最热）+ 分类筛选行，主体为 3 列封面网格
class HomePage extends ConsumerStatefulWidget
{
    const HomePage({super.key});

    @override
    ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
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

    /// 排序 Tab：对齐禁漫官方语义，时间筛选即热度排行
    static const _sortTabs = [
        _SortTabDef('最新', 'mr', 'a'),
        _SortTabDef('今日最热', 'mv', 't'),
        _SortTabDef('本周最热', 'mv', 'w'),
        _SortTabDef('本月最热', 'mv', 'm'),
    ];

    String _selectedCategory = '0';
    int _selectedTabIndex = 0;

    /// 当前选中的排序 Tab
    _SortTabDef get _currentTab => _sortTabs[_selectedTabIndex];

    @override
    void initState()
    {
        super.initState();
        Future.microtask(() => _loadResults());
    }

    /// 按当前筛选条件加载列表
    Future<void> _loadResults()
    {
        return ref.read(categoryProvider.notifier).loadCategory(
            category: _selectedCategory,
            orderBy: _currentTab.orderBy,
            time: _currentTab.time,
        );
    }

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(categoryProvider);

        return Scaffold(
            appBar: AppBar(
                title: const Text('七星天堂'),
                actions: [
                    IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => context.push('/search'),
                    ),
                ],
            ),
            body: Column(
                children: [
                    // 排序 Tab（最新/今日最热/本周最热/本月最热）
                    _buildSortTabs(),
                    const SizedBox(height: 4),
                    // 分类选择
                    _buildCategoryChips(),
                    Divider(color: context.appColors.divider),
                    // 结果列表
                    Expanded(child: _buildResults(state)),
                ],
            ),
        );
    }

    /// 构建排序 Tab 行（4 个 Tab 平分宽度，选中态为主题色 + 底部指示条）
    Widget _buildSortTabs()
    {
        return SizedBox(
            height: 40,
            child: Row(
                children: [
                    for (var i = 0; i < _sortTabs.length; i++)
                        Expanded(child: _buildSortTab(i)),
                ],
            ),
        );
    }

    /// 构建单个排序 Tab
    Widget _buildSortTab(int index)
    {
        final tab = _sortTabs[index];
        final isSelected = _selectedTabIndex == index;
        return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ()
            {
                if (isSelected) return;
                setState(() => _selectedTabIndex = index);
                _loadResults();
            },
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Text(
                        tab.label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected
                                ? context.appColors.accent
                                : context.appColors.textSecondary,
                        ),
                    ),
                    const SizedBox(height: 4),
                    // 底部选中指示条
                    Container(
                        width: 24,
                        height: 2,
                        decoration: BoxDecoration(
                            color: isSelected
                                ? context.appColors.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(1),
                        ),
                    ),
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
                            _loadResults();
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
            return const AlbumGridSkeleton();
        }

        if (state.error != null && state.results.isEmpty)
        {
            return AppErrorWidget(
                message: state.error!,
                onRetry: _loadResults,
            );
        }

        if (state.results.isEmpty)
        {
            return Center(
                child: Text(
                    '暂无数据',
                    style: TextStyle(color: context.appColors.textSecondary),
                ),
            );
        }

        // 下拉刷新 + 触底加载更多
        return RefreshIndicator(
            color: context.appColors.accent,
            backgroundColor: context.appColors.surface,
            onRefresh: _loadResults,
            child: NotificationListener<ScrollNotification>(
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
                    physics: const AlwaysScrollableScrollPhysics(),
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
            ),
        );
    }
}
