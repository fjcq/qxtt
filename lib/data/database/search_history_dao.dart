import '../models/search_history_model.dart';

/// 搜索历史数据访问对象（内存存储）
class SearchHistoryDao
{
    final List<SearchHistoryModel> _history = [];

    /// 添加搜索历史
    Future<void> addHistory(String keyword) async
    {
        _history.removeWhere((h) => h.keyword == keyword);
        _history.insert(0, SearchHistoryModel(
            keyword: keyword,
            searchedAt: DateTime.now().toIso8601String(),
        ));
    }

    /// 获取所有搜索历史
    Future<List<SearchHistoryModel>> getAllHistory() async
    {
        return List.from(_history);
    }

    /// 删除搜索历史
    Future<void> deleteHistory(String keyword) async
    {
        _history.removeWhere((h) => h.keyword == keyword);
    }

    /// 清空所有搜索历史
    Future<void> clearAllHistory() async
    {
        _history.clear();
    }
}
