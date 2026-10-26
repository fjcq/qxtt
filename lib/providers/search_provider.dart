import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import '../core/jm/jm_image.dart';
import '../data/database/task_dao.dart';
import '../data/database/library_dao.dart';
import '../data/database/search_history_dao.dart';
import '../data/models/search_history_model.dart';
import '../data/database/browse_history_dao.dart';
import 'browse_history_provider.dart';
import 'config_provider.dart';
import '../utils/library_storage.dart';

/// JmClient Provider
/// 仅监听影响客户端构造的代理特征值（useProxy + proxyUrl），
/// 避免 ConfigState 其他字段变化（如主题、缓存大小、isLoading 翻转）触发
/// 客户端及所有下游 Provider（搜索/分类/详情）无意义重建导致页面数据丢失
final jmClientProvider = Provider<JmClient>((ref)
{
    // 代理特征值：启用代理时为 proxyUrl，未启用时为空串
    final proxySig = ref.watch(configProvider.select((s)
    {
        final c = s.config;
        return c.useProxy && c.proxyUrl.isNotEmpty ? c.proxyUrl : '';
    }));
    final proxyUrl = proxySig.isEmpty ? null : proxySig;
    final useProxy = proxySig.isNotEmpty;
    final client = JmClient(
        proxyUrl: proxyUrl,
        useProxy: useProxy,
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

/// 搜索类型映射：显示名称 → main_tag 参数值
/// 站内=0, 作品=1, 作者=2, 标签=3, 角色=4
const kSearchTypeMap = {
    '站内': 0,
    '作品': 1,
    '作者': 2,
    '标签': 3,
    '角色': 4,
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
    final int searchType;
    final List<SearchHistoryModel> history;

    const SearchState({
        this.results = const [],
        this.isLoading = false,
        this.error,
        this.currentPage = 1,
        this.totalPages = 0,
        this.total = 0,
        this.query = '',
        this.searchType = 0,
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
        int? searchType,
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
    Future<void> search(String query, {int? type, int page = 1}) async
    {
        final searchType = type ?? state.searchType;
        state = state.copyWith(isLoading: true, error: null, query: query, searchType: searchType);

        // 保存搜索历史
        await _historyDao.addHistory(query);
        final updatedHistory = await _historyDao.getAllHistory();

        try
        {
            final result = await _client.search(query, page: page, mainTag: searchType);
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
    void setSearchType(int type)
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

    /// 异步计算得到的总页数（当 API 未返回 page_count 时启用）
    final int totalPageCount;

    /// 是否正在计算总页数
    final bool isLoadingPageCount;

    /// 本子的浏览历史记录（含阅读进度，未读过为 null）
    final BrowseHistoryModel? history;

    /// 当前展示的详情是否来自本地数据（本地优先或网络失败兜底）
    final bool isOfflineFallback;

    /// 是否正在后台尝试联网刷新（本地内容已展示时为 true）
    final bool isRefreshing;

    const AlbumDetailState({
        this.detail,
        this.isLoading = false,
        this.error,
        this.totalPageCount = 0,
        this.isLoadingPageCount = false,
        this.history,
        this.isOfflineFallback = false,
        this.isRefreshing = false,
    });

    /// 用于 UI 显示的总页数，优先使用异步计算结果
    int get displayPageCount
    {
        if (totalPageCount > 0) return totalPageCount;
        return detail?.pageCount ?? 0;
    }

    /// 是否存在有效的阅读进度（可用于"继续阅读"入口）
    bool get hasReadProgress
    {
        final h = history;
        return h != null && h.lastReadPhotoId != null && h.lastReadPhotoId!.isNotEmpty;
    }

    AlbumDetailState copyWith({
        AlbumDetail? detail,
        bool? isLoading,
        String? error,
        int? totalPageCount,
        bool? isLoadingPageCount,
        BrowseHistoryModel? history,
        bool? isOfflineFallback,
        bool? isRefreshing,
    })
    {
        return AlbumDetailState(
            detail: detail ?? this.detail,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            totalPageCount: totalPageCount ?? this.totalPageCount,
            isLoadingPageCount: isLoadingPageCount ?? this.isLoadingPageCount,
            history: history ?? this.history,
            isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
            isRefreshing: isRefreshing ?? this.isRefreshing,
        );
    }
}

/// 本子详情 Provider
class AlbumDetailNotifier extends StateNotifier<AlbumDetailState>
{
    final JmClient _client;

    /// 浏览历史数据访问对象（记录浏览 + 读取上次阅读进度）
    final BrowseHistoryDao _historyDao;

    /// 书架数据访问对象（网络失败时读取本地下载信息）
    final LibraryDao _libraryDao;

    /// Provider 引用，用于读取下载目录配置
    final Ref _ref;

    AlbumDetailNotifier(this._client, this._historyDao, this._libraryDao, this._ref)
        : super(const AlbumDetailState());

    /// 加载本子详情（本地优先 + 后台联网刷新）
    ///
    /// 先读取本地书架与下载元数据并立即展示已下载内容，
    /// 避免弱网/断网时长时间停留在网络等待；随后后台请求完整详情：
    ///   - 成功：替换为完整详情（含全部章节），离线标记自动清除
    ///   - 失败：保留本地内容，仅结束刷新状态
    ///
    /// 本地没有已下载内容时，行为与原先一致（加载中 → 详情或错误）。
    Future<void> loadDetail(String albumId) async
    {
        // 先标记加载中，避免页面重建时重复触发 loadDetail
        state = const AlbumDetailState(isLoading: true);

        // 本地优先：读取本地已下载内容并立即展示
        final localDetail = await _buildOfflineDetail(albumId);
        final localHistory = await _readHistorySafe(albumId);
        if (localDetail != null)
        {
            state = AlbumDetailState(
                detail: localDetail,
                history: localHistory,
                isOfflineFallback: true,
                isRefreshing: true,
            );
        }

        // 后台联网刷新：成功替换为完整详情，失败保留本地内容
        try
        {
            final detail = await _client.getAlbumDetail(albumId);

            // 记录浏览历史（DAO 层保留已有阅读进度）
            try
            {
                await _historyDao.addHistory(BrowseHistoryModel()
                    ..albumId = detail.albumId
                    ..title = detail.name
                    ..coverUrl = _client.getAlbumCoverUrl(detail.albumId)
                    ..author = detail.author
                    ..browsedAt = DateTime.now().toIso8601String()
                    ..lastReadPage = 0,
                );
            }
            catch (_)
            {
                // 历史记录失败不影响详情展示
            }

            final history = await _readHistorySafe(albumId);
            state = AlbumDetailState(detail: detail, history: history);

            // API 不再返回 page_count，异步统计各章节图片总数以显示真实总页数
            if (detail.pageCount <= 0 && detail.episodes.isNotEmpty)
            {
                unawaited(_calculateTotalPageCount(detail));
            }
        }
        catch (e)
        {
            if (localDetail != null)
            {
                // 网络仍不可用：保留已展示的本地内容，仅结束刷新状态
                state = state.copyWith(isRefreshing: false);
                return;
            }
            state = AlbumDetailState(error: e.toString());
        }
    }

    /// 读取浏览历史（失败返回 null，不影响详情展示）
    Future<BrowseHistoryModel?> _readHistorySafe(String albumId) async
    {
        try
        {
            return await _historyDao.getHistory(albumId);
        }
        catch (_)
        {
            return null;
        }
    }

    /// 使用本地书架与下载元数据重建本子详情（离线兜底）
    ///
    /// 仅包含本地已下载的章节，返回值非 null 表示可以离线阅读。
    Future<AlbumDetail?> _buildOfflineDetail(String albumId) async
    {
        try
        {
            final album = await _libraryDao.getByAlbumId(albumId);
            if (album == null)
            {
                return null;
            }

            // 等待配置就绪后解析真实的下载根目录
            await _ref.read(configProvider.notifier).initialized;
            final configured = _ref.read(configProvider).config.downloadDir;
            final downloadDir = await LibraryStorage.getDownloadDir(configured: configured);
            final albumDir = await LibraryStorage.resolveAlbumDir(
                album,
                downloadDir: downloadDir,
            );
            if (!await Directory(albumDir).exists())
            {
                return null;
            }

            final (meta, _, _) = await LibraryStorage.loadAlbumMetadataWithChapters(albumDir);
            final downloaded = album.downloadedEpisodes.toSet();
            var episodes = meta?.episodes ?? const <Episode>[];

            // 优先仅保留真正下载完成的章节，避免把未下载章节也列入离线列表
            if (downloaded.isNotEmpty)
            {
                final filtered = episodes
                    .where((e) => downloaded.contains(e.photoId))
                    .toList();
                if (filtered.isNotEmpty)
                {
                    episodes = filtered;
                }
            }
            // 元数据缺失时，直接以书架记录的已下载章节兜底
            if (episodes.isEmpty)
            {
                episodes = downloaded
                    .map((photoId) => Episode(
                        photoId: photoId,
                        index: '',
                        name: photoId,
                    ))
                    .toList();
            }
            if (episodes.isEmpty)
            {
                return null;
            }

            final sorted = List<Episode>.from(episodes)
                ..sort((a, b) => _compareEpisodeIndex(a.index, b.index));

            return AlbumDetail(
                albumId: album.albumId,
                name: (meta?.name.isNotEmpty ?? false) ? meta!.name : album.title,
                author: (meta?.author.isNotEmpty ?? false) ? meta!.author : album.author,
                pageCount: (meta?.pageCount ?? 0) > 0 ? meta!.pageCount : album.pageCount,
                episodeCount: sorted.length,
                episodes: sorted,
            );
        }
        catch (_)
        {
            return null;
        }
    }

    /// 比较章节序号：优先按数字大小，非数字回退到字符串比较
    int _compareEpisodeIndex(String a, String b)
    {
        final numA = int.tryParse(a);
        final numB = int.tryParse(b);
        if (numA != null && numB != null)
        {
            return numA.compareTo(numB);
        }
        return a.compareTo(b);
    }

    /// 分批并发获取章节详情，统计本子总页数
    /// 限制并发数以避免对服务器造成过大压力
    Future<void> _calculateTotalPageCount(AlbumDetail detail) async
    {
        state = state.copyWith(isLoadingPageCount: true);
        const concurrency = 5;
        var total = 0;

        try
        {
            final episodes = detail.episodes;
            for (var i = 0; i < episodes.length; i += concurrency)
            {
                final batch = episodes.skip(i).take(concurrency).toList();
                final futures = batch.map(
                    (episode) => _client.getPhotoDetail(episode.photoId),
                );
                final photoDetails = await Future.wait(futures);
                for (final photo in photoDetails)
                {
                    total += photo.pageArr.length;
                }
            }

            state = state.copyWith(
                totalPageCount: total,
                isLoadingPageCount: false,
            );
        }
        catch (e)
        {
            state = state.copyWith(isLoadingPageCount: false);
        }
    }
}

/// 本子详情 Provider 工厂
final albumDetailProvider = StateNotifierProvider.family<AlbumDetailNotifier, AlbumDetailState, String>((ref, albumId)
{
    final client = ref.watch(jmClientProvider);
    final historyDao = ref.watch(browseHistoryDaoProvider);
    final libraryDao = ref.watch(libraryDaoProvider);
    return AlbumDetailNotifier(client, historyDao, libraryDao, ref);
});

