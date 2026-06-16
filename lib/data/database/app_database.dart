/// 应用数据库管理（简化版，使用内存存储）
class AppDatabase
{
    /// 单例实例
    static final AppDatabase _instance = AppDatabase._internal();

    /// 工厂构造函数
    factory AppDatabase() => _instance;

    /// 私有构造函数
    AppDatabase._internal();

    /// 初始化
    Future<void> init() async {}

    /// 关闭
    Future<void> close() async {}
}
