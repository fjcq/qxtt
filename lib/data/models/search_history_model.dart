/// 搜索历史模型
class SearchHistoryModel
{
    /// 搜索关键词
    late String keyword;

    /// 搜索时间
    late String searchedAt;

    /// 构造函数
    SearchHistoryModel({
        required this.keyword,
        required this.searchedAt,
    });
}
