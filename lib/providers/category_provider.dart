import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import 'search_provider.dart';

/// 分类浏览状态
class CategoryState
{
    final List<SearchItem> results;
    final bool isLoading;
    final String? error;
    final int currentPage;

    /// 分类值（'0'=全部）
    final String category;

    /// 时间范围（'a'=全部, 't'=今日, 'w'=本周, 'm'=本月）
    final String time;

    /// 排序方式（'mr'=最新, 'mv'=最热）
    final String orderBy;

    const CategoryState({
        this.results = const [],
        this.isLoading = false,
        this.error,
        this.currentPage = 1,
        this.category = '0',
        this.time = 'a',
        this.orderBy = 'mr',
    });

    CategoryState copyWith({
        List<SearchItem>? results,
        bool? isLoading,
        String? error,
        int? currentPage,
        String? category,
        String? time,
        String? orderBy,
    })
    {
        return CategoryState(
            results: results ?? this.results,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            currentPage: currentPage ?? this.currentPage,
            category: category ?? this.category,
            time: time ?? this.time,
            orderBy: orderBy ?? this.orderBy,
        );
    }
}

/// 分类浏览 Provider
class CategoryNotifier extends StateNotifier<CategoryState>
{
    final JmClient? _client;

    /// 请求序号：用于丢弃快速切换筛选时晚到的旧请求响应，避免竞态覆盖
    int _requestSeq = 0;

    CategoryNotifier(this._client) : super(const CategoryState());

    /// 加载分类
    Future<void> loadCategory({
        String category = '0',
        String time = 'a',
        String orderBy = 'mr',
        int page = 1,
    }) async
    {
        if (_client == null)
        {
            state = state.copyWith(isLoading: false);
            return;
        }

        // 分配请求序号，闭包捕获用于响应校验
        final seq = ++_requestSeq;
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final result = await _client.categoriesFilter(
                page: page,
                category: category,
                orderBy: orderBy,
                time: time,
            );

            // 响应晚到（已被更新的切换请求取代）则丢弃，防止旧数据覆盖新筛选结果
            if (seq != _requestSeq) return;

            state = state.copyWith(
                results: page == 1
                    ? result.results
                    : [...state.results, ...result.results],
                isLoading: false,
                currentPage: page,
                category: category,
                time: time,
                orderBy: orderBy,
            );
        }
        catch (e)
        {
            if (seq != _requestSeq) return;
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 加载更多
    Future<void> loadMore() async
    {
        if (state.isLoading) return;
        await loadCategory(
            category: state.category,
            time: state.time,
            orderBy: state.orderBy,
            page: state.currentPage + 1,
        );
    }
}

/// 分类浏览 Provider 实例
final categoryProvider = StateNotifierProvider<CategoryNotifier, CategoryState>((ref)
{
    final client = ref.watch(jmClientProvider);
    return CategoryNotifier(client);
});
