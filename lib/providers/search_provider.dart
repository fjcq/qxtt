import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import '../data/database/app_database.dart';
import '../data/database/task_dao.dart';
import '../data/database/library_dao.dart';
import '../data/database/search_history_dao.dart';

/// 数据库 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref)
{
    final db = AppDatabase();
    ref.onDispose(() async => await db.close());
    return db;
});

/// JmClient Provider
final jmClientProvider = Provider<JmClient>((ref)
{
    return JmClient();
});

/// TaskDao Provider
final taskDaoProvider = Provider<TaskDao>((ref)
{
    return TaskDao();
});

/// LibraryDao Provider
final libraryDaoProvider = Provider<LibraryDao>((ref)
{
    return LibraryDao();
});

/// SearchHistoryDao Provider
final searchHistoryDaoProvider = Provider<SearchHistoryDao>((ref)
{
    return SearchHistoryDao();
});

// ===== 以下为手动实现的 Notifier（不使用代码生成） =====

/// 搜索状态
class SearchState
{
    final List<SearchItem> results;
    final bool isLoading;
    final String? error;
    final int currentPage;
    final int totalPages;
    final int total;
    final String query;

    const SearchState({
        this.results = const [],
        this.isLoading = false,
        this.error,
        this.currentPage = 1,
        this.totalPages = 0,
        this.total = 0,
        this.query = '',
    });

    SearchState copyWith({
        List<SearchItem>? results,
        bool? isLoading,
        String? error,
        int? currentPage,
        int? totalPages,
        int? total,
        String? query,
    })
    {
        return SearchState(
            results: results ?? this.results,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            currentPage: currentPage ?? this.currentPage,
            totalPages: totalPages ?? this.totalPages,
            total: total ?? this.total,
            query: query ?? this.query,
        );
    }
}

/// 搜索 Provider
class SearchNotifier extends StateNotifier<SearchState>
{
    final JmClient _client;

    SearchNotifier(this._client) : super(const SearchState());

    /// 执行搜索
    Future<void> search(String query, {String type = 'site', int page = 1}) async
    {
        state = state.copyWith(isLoading: true, error: null, query: query);

        try
        {
            final result = await _client.search(query, page: page, searchType: type);
            state = state.copyWith(
                results: page == 1
                    ? result.results
                    : [...state.results, ...result.results],
                isLoading: false,
                currentPage: page,
                totalPages: result.pageCount,
                total: result.total,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 加载更多
    Future<void> loadMore({String type = 'site'}) async
    {
        if (state.isLoading) return;
        if (state.currentPage >= state.totalPages) return;

        await search(state.query, type: type, page: state.currentPage + 1);
    }

    /// 清空搜索
    void clear()
    {
        state = const SearchState();
    }
}

/// 搜索 Provider 实例
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref)
{
    final client = ref.watch(jmClientProvider);
    return SearchNotifier(client);
});

/// 本子详情状态
class AlbumDetailState
{
    final AlbumDetail? detail;
    final bool isLoading;
    final String? error;

    const AlbumDetailState({
        this.detail,
        this.isLoading = false,
        this.error,
    });
}

/// 本子详情 Provider
class AlbumDetailNotifier extends StateNotifier<AlbumDetailState>
{
    final JmClient _client;

    AlbumDetailNotifier(this._client) : super(const AlbumDetailState());

    /// 加载本子详情
    Future<void> loadDetail(String albumId) async
    {
        state = const AlbumDetailState(isLoading: true);

        try
        {
            final detail = await _client.getAlbumDetail(albumId);
            state = AlbumDetailState(detail: detail);
        }
        catch (e)
        {
            state = AlbumDetailState(error: e.toString());
        }
    }
}

/// 本子详情 Provider 工厂
final albumDetailProvider = StateNotifierProvider.family<AlbumDetailNotifier, AlbumDetailState, String>((ref, albumId)
{
    final client = ref.watch(jmClientProvider);
    return AlbumDetailNotifier(client);
});

/// 分类浏览状态
class CategoryState
{
    final List<SearchItem> results;
    final bool isLoading;
    final String? error;
    final int currentPage;
    final String category;
    final String time;

    const CategoryState({
        this.results = const [],
        this.isLoading = false,
        this.error,
        this.currentPage = 1,
        this.category = '0',
        this.time = 'a',
    });

    CategoryState copyWith({
        List<SearchItem>? results,
        bool? isLoading,
        String? error,
        int? currentPage,
        String? category,
        String? time,
    })
    {
        return CategoryState(
            results: results ?? this.results,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            currentPage: currentPage ?? this.currentPage,
            category: category ?? this.category,
            time: time ?? this.time,
        );
    }
}

/// 分类浏览 Provider
class CategoryNotifier extends StateNotifier<CategoryState>
{
    final JmClient _client;

    CategoryNotifier(this._client) : super(const CategoryState());

    /// 加载分类
    Future<void> loadCategory({
        String category = '0',
        String time = 'a',
        String orderBy = 'mr',
        int page = 1,
    }) async
    {
        state = state.copyWith(isLoading: true, error: null);

        try
        {
            final result = await _client.categoriesFilter(
                page: page,
                category: category,
                orderBy: orderBy,
                time: time,
            );
            state = state.copyWith(
                results: page == 1
                    ? result.results
                    : [...state.results, ...result.results],
                isLoading: false,
                currentPage: page,
                category: category,
                time: time,
            );
        }
        catch (e)
        {
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
