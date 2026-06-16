import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/browse_history_dao.dart';

/// 浏览历史状态
class BrowseHistoryState
{
    /// 历史列表
    final List<BrowseHistoryModel> history;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    const BrowseHistoryState({
        this.history = const [],
        this.isLoading = false,
        this.error,
    });

    BrowseHistoryState copyWith({
        List<BrowseHistoryModel>? history,
        bool? isLoading,
        String? error,
    })
    {
        return BrowseHistoryState(
            history: history ?? this.history,
            isLoading: isLoading ?? this.isLoading,
            error: error,
        );
    }
}

/// 浏览历史 Provider
class BrowseHistoryNotifier extends StateNotifier<BrowseHistoryState>
{
    final BrowseHistoryDao _dao;

    BrowseHistoryNotifier(this._dao) : super(const BrowseHistoryState());

    /// 加载历史记录
    Future<void> loadHistory() async
    {
        state = state.copyWith(isLoading: true, error: null);
        try
        {
            final history = await _dao.getAllHistory();
            state = state.copyWith(history: history, isLoading: false);
        }
        catch (e)
        {
            state = state.copyWith(isLoading: false, error: e.toString());
        }
    }

    /// 添加浏览记录
    Future<void> addHistory(BrowseHistoryModel item) async
    {
        await _dao.addHistory(item);
        await loadHistory();
    }

    /// 删除单条历史
    Future<void> deleteHistory(String albumId) async
    {
        await _dao.deleteHistory(albumId);
        await loadHistory();
    }

    /// 清空所有历史
    Future<void> clearAllHistory() async
    {
        await _dao.clearAllHistory();
        await loadHistory();
    }
}

/// BrowseHistoryDao Provider
final browseHistoryDaoProvider = Provider<BrowseHistoryDao>((ref)
{
    return BrowseHistoryDao();
});

/// 浏览历史 Provider 实例
final browseHistoryProvider = StateNotifierProvider<BrowseHistoryNotifier, BrowseHistoryState>((ref)
{
    final dao = ref.watch(browseHistoryDaoProvider);
    return BrowseHistoryNotifier(dao);
});
