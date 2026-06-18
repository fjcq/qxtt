/// 单个域名的健康历史（在内存中累积，多次测试不持久化）
class DomainHealth
{
    final int totalTests;
    final int successTests;

    const DomainHealth({required this.totalTests, required this.successTests});

    double get successRate => totalTests == 0 ? 0 : successTests / totalTests;

    static const empty = DomainHealth(totalTests: 0, successTests: 0);

    DomainHealth add(bool success) => DomainHealth(
        totalTests: totalTests + 1,
        successTests: successTests + (success ? 1 : 0),
    );

    /// 健康档位：基于成功率
    /// 0: 健康 (>= 80%)   → 绿
    /// 1: 警告 (50~80%)   → 黄
    /// 2: 不健康 (< 50%)  → 橙
    /// 3: 未知 (< 3 次)   → 灰
    int get healthLevel
    {
        if (totalTests < 3) return 3;
        if (successRate >= 0.8) return 0;
        if (successRate >= 0.5) return 1;
        return 2;
    }

    String get displayHealth
    {
        if (totalTests == 0) return '';
        return '$successTests/$totalTests';
    }
}
