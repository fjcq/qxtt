import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/album_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';

/// 搜索页
class SearchPage extends ConsumerStatefulWidget
{
    /// 初始搜索关键词
    final String? initialQuery;

    const SearchPage({super.key, this.initialQuery});

    @override
    ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
{
    final _searchController = TextEditingController();
    final _searchFocusNode = FocusNode();

    /// 搜索类型列表（显示名称）
    static final _searchTypeLabels = kSearchTypeMap.keys.toList();

    /// 当前选中的搜索类型索引
    int _currentTypeIndex = 0;

    @override
    void initState()
    {
        super.initState();
        if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty)
        {
            _searchController.text = widget.initialQuery!;
            Future.microtask(() =>
                ref.read(searchProvider.notifier).search(widget.initialQuery!),
            );
        }
        else
        {
            // 无初始查询时自动弹出键盘
            Future.microtask(() => _searchFocusNode.requestFocus());
        }
    }

    @override
    void dispose()
    {
        _searchController.dispose();
        _searchFocusNode.dispose();
        super.dispose();
    }

    /// 执行搜索
    void _doSearch(String query)
    {
        if (query.trim().isEmpty) return;
        _searchFocusNode.unfocus();
        final mainTag = kSearchTypeMap[_searchTypeLabels[_currentTypeIndex]] ?? 0;
        ref.read(searchProvider.notifier).search(
            query.trim(),
            type: mainTag,
        );
    }

    /// 切换搜索类型
    void _onTypeChanged(int index)
    {
        setState(() => _currentTypeIndex = index);
        final mainTag = kSearchTypeMap[_searchTypeLabels[index]] ?? 0;
        ref.read(searchProvider.notifier).setSearchType(mainTag);
    }

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(searchProvider);
        final hasResults = state.results.isNotEmpty || state.isLoading;

        return Scaffold(
            appBar: AppBar(
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                ),
                titleSpacing: 0,
                title: _buildSearchField(),
                actions: [
                    TextButton(
                        onPressed: () => _doSearch(_searchController.text),
                        child: Text(
                            '搜索',
                            style: TextStyle(
                                color: context.appColors.accent,
                                fontSize: 15,
                            ),
                        ),
                    ),
                ],
            ),
            body: hasResults
                ? _buildResults(context, ref, state)
                : _buildHistoryAndSuggestions(state),
        );
    }

    /// 构建搜索输入框（AppBar 内）
    Widget _buildSearchField()
    {
        return TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 15,
            ),
            decoration: InputDecoration(
                hintText: '搜索漫画...',
                hintStyle: TextStyle(color: context.appColors.textDisabled),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (_, value, __)
                    {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                            icon: Icon(
                                Icons.clear,
                                color: context.appColors.textSecondary,
                                size: 18,
                            ),
                            onPressed: ()
                            {
                                _searchController.clear();
                                ref.read(searchProvider.notifier).clear();
                            },
                        );
                    },
                ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _doSearch,
        );
    }

    /// 构建搜索历史和搜索类型区域（无搜索结果时显示）
    Widget _buildHistoryAndSuggestions(SearchState state)
    {
        return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    const SizedBox(height: 12),
                    // 搜索类型切换
                    _buildSearchTypeChips(),
                    const SizedBox(height: 20),
                    // 搜索历史
                    if (state.history.isNotEmpty) ...[
                        _buildHistoryHeader(),
                        const SizedBox(height: 8),
                        _buildHistoryList(state),
                    ],
                    // 空状态
                    if (state.history.isEmpty)
                        Center(
                            child: Padding(
                                padding: const EdgeInsets.only(top: 60),
                                child: Text(
                                    '输入关键词开始搜索',
                                    style: TextStyle(
                                        color: context.appColors.textDisabled,
                                        fontSize: 14,
                                    ),
                                ),
                            ),
                        ),
                ],
            ),
        );
    }

    /// 构建搜索类型切换标签
    Widget _buildSearchTypeChips()
    {
        return SizedBox(
            height: 36,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _searchTypeLabels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index)
                {
                    final isSelected = index == _currentTypeIndex;
                    return GestureDetector(
                        onTap: () => _onTypeChanged(index),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                            ),
                            decoration: BoxDecoration(
                                color: isSelected
                                    ? context.appColors.accent
                                    : context.appColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                                _searchTypeLabels[index],
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? context.appColors.background
                                        : context.appColors.textSecondary,
                                ),
                            ),
                        ),
                    );
                },
            ),
        );
    }

    /// 构建搜索历史标题栏
    Widget _buildHistoryHeader()
    {
        return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Text(
                    '搜索历史',
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                    ),
                ),
                GestureDetector(
                    onTap: () => ref.read(searchProvider.notifier).clearHistory(),
                    child: Text(
                        '清空',
                        style: TextStyle(
                            color: context.appColors.textDisabled,
                            fontSize: 13,
                        ),
                    ),
                ),
            ],
        );
    }

    /// 构建搜索历史列表
    Widget _buildHistoryList(SearchState state)
    {
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.history.map((item)
            {
                final keyword = item.keyword;
                return GestureDetector(
                    onTap: ()
                    {
                        _searchController.text = keyword;
                        _doSearch(keyword);
                    },
                    onLongPress: () => ref.read(searchProvider.notifier).deleteHistory(keyword),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                        ),
                        decoration: BoxDecoration(
                            color: context.appColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                            keyword,
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 13,
                            ),
                        ),
                    ),
                );
            }).toList(),
        );
    }

    /// 构建搜索结果列表
    Widget _buildResults(BuildContext context, WidgetRef ref, SearchState state)
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
            return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(
                            Icons.search_off,
                            size: 48,
                            color: context.appColors.textDisabled,
                        ),
                        const SizedBox(height: 12),
                        Text(
                            '没有找到 "${state.query}" 的结果',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                    ],
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
                    // 搜索类型切换（结果页顶部）
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: _buildSearchTypeChips(),
                        ),
                    ),
                    // 结果数量
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Text(
                                '共 ${state.total} 条结果',
                                style: TextStyle(
                                    color: context.appColors.textDisabled,
                                    fontSize: 12,
                                ),
                            ),
                        ),
                    ),
                    // 结果网格
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
                                        key: ValueKey(album.id),
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
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                    child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.appColors.accent,
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
                                    '第 ${state.currentPage} / ${state.totalPages} 页',
                                    style: TextStyle(
                                        color: context.appColors.textDisabled,
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
