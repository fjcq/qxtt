import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import '../core/jm/jm_image.dart';
import '../data/database/app_database.dart';
import '../data/database/task_dao.dart';
import '../data/database/library_dao.dart';
import '../data/database/search_history_dao.dart';
import '../data/models/search_history_model.dart';
import 'config_provider.dart';

/// 数据库 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref)
{
    final db = AppDatabase();
    ref.onDispose(() async => await db.close());
    return db;
});

/// JmClient Provider
/// 监听 configProvider 的代理配置，配置变更时自动重建客户端
final jmClientProvider = Provider<JmClient>((ref)
{
    final config = ref.watch(configProvider).config;
    final proxyUrl = config.useProxy && config.proxyUrl.isNotEmpty
        ? config.proxyUrl
        : null;
    final client = JmClient(
        proxyUrl: proxyUrl,
        useProxy: config.useProxy,
    );
    // 同步重置图片缓存管理器（让它下次访问时使用新代理 + 新域名列表）
    // imageDomainProvider 用闭包延迟获取 client.imageDomainList，
    // 保证 JmClient.updateApiDomains() 自动更新后缓存管理器能立即看到
    JmImageCacheManager.reset(
        proxyUrl: proxyUrl,
        imageDomainProvider: () => client.imageDomainList,
    );
    ref.onDispose(() async => client.dio.close(force: true));
    return client;
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

/// 搜索类型映射：显示名称 → API 参数值
const kSearchTypeMap = {
    '站内': 'site',
    '作者': 'author',
    '标签': 'tag',
    '作品': 'work',
    '角色': 'character',
};

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
    final String searchType;
    final List<SearchHistoryModel> history;

    const SearchState({
        this.results = const [],
        this.isLoading = false,
        this.error,
        this.currentPage = 1,
        this.totalPages = 0,
        this.total = 0,
        this.query = '',
        this.searchType = 'site',
        this.history = const [],
    });

    SearchState copyWith({
        List<SearchItem>? results,
        bool? isLoading,
        String? error,
        int? currentPage,
        int? totalPages,
        int? total,
        String? query,
        String? searchType,
        List<SearchHistoryModel>? history,
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
            searchType: searchType ?? this.searchType,
            history: history ?? this.history,
        );
    }
}

/// 搜索 Provider
class SearchNotifier extends StateNotifier<SearchState>
{
    final JmClient _client;
    final SearchHistoryDao _historyDao;

    SearchNotifier(this._client, this._historyDao) : super(const SearchState())
    {
        _loadHistory();
    }

    /// 加载搜索历史
    Future<void> _loadHistory() async
    {
        final history = await _historyDao.getAllHistory();
        state = state.copyWith(history: history);
    }

    /// 执行搜索
    Future<void> search(String query, {String? type, int page = 1}) async
    {
        final searchType = type ?? state.searchType;
        state = state.copyWith(isLoading: true, error: null, query: query, searchType: searchType);

        // 保存搜索历史
        await _historyDao.addHistory(query);
        final updatedHistory = await _historyDao.getAllHistory();

        try
        {
            final result = await _client.search(query, page: page, searchType: searchType);
            state = state.copyWith(
                results: page == 1
                    ? result.results
                    : [...state.results, ...result.results],
                isLoading: false,
                currentPage: page,
                totalPages: result.pageCount,
                total: result.total,
                history: updatedHistory,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString(), history: updatedHistory);
        }
    }

    /// 切换搜索类型
    void setSearchType(String type)
    {
        state = state.copyWith(searchType: type);
        // 如果已有查询词，用新类型重新搜索
        if (state.query.isNotEmpty)
        {
            search(state.query, type: type);
        }
    }

    /// 加载更多
    Future<void> loadMore() async
    {
        if (state.isLoading) return;
        if (state.currentPage >= state.totalPages) return;

        await search(state.query, page: state.currentPage + 1);
    }

    /// 删除单条搜索历史
    Future<void> deleteHistory(String keyword) async
    {
        await _historyDao.deleteHistory(keyword);
        final updatedHistory = await _historyDao.getAllHistory();
        state = state.copyWith(history: updatedHistory);
    }

    /// 清空搜索历史
    Future<void> clearHistory() async
    {
        await _historyDao.clearAllHistory();
        state = state.copyWith(history: []);
    }

    /// 清空搜索结果
    void clear()
    {
        state = state.copyWith(
            results: const [],
            query: '',
            currentPage: 1,
            totalPages: 0,
            total: 0,
            error: null,
        );
    }
}

/// 搜索 Provider 实例
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref)
{
    final client = ref.watch(jmClientProvider);
    final historyDao = ref.watch(searchHistoryDaoProvider);
    return SearchNotifier(client, historyDao);
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
