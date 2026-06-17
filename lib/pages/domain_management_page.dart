import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_config.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';

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

/// 域名管理页
/// 提供：
///   1. API / 图片 域名 Tab 切换
///   2. 域名列表（拖拽顺序 + 上下移 + 删除 + 测速结果 + 健康历史）
///   3. 顶部操作：刷新最新 / 测试全部 / 随机打乱 / 按速度排序 / 恢复默认 / 添加
///   4. 测速进度条（流式）
class DomainManagementPage extends ConsumerStatefulWidget
{
    const DomainManagementPage({super.key});

    @override
    ConsumerState<DomainManagementPage> createState()
        => _DomainManagementPageState();
}

class _DomainManagementPageState extends ConsumerState<DomainManagementPage>
    with SingleTickerProviderStateMixin
{
    late final TabController _tab;

    /// API 域名当前列表（页面内编辑用，未点"应用"前不影响 client）
    late List<String> _apiList;

    /// 图片域名当前列表
    late List<String> _imageList;

    /// API 域名测速结果（domain -> DomainTestResult）
    final Map<String, DomainTestResult> _apiTestResults = {};

    /// 图片域名测速结果
    final Map<String, DomainTestResult> _imageTestResults = {};

    /// API 域名健康历史
    final Map<String, DomainHealth> _apiHealth = {};

    /// 图片域名健康历史
    final Map<String, DomainHealth> _imageHealth = {};

    /// 是否正在测速
    bool _testing = false;

    /// 测速进度：0.0 ~ 1.0
    double _testProgress = 0;

    /// 测速总数
    int _testTotal = 0;

    /// 是否正在刷新最新
    bool _refreshing = false;

    /// 当前测速任务的订阅
    StreamSubscription<DomainTestResult>? _testSub;

    @override
    void initState()
    {
        super.initState();
        _tab = TabController(length: 2, vsync: this);
        final client = ref.read(jmClientProvider);
        _apiList = List<String>.from(client.domainList);
        _imageList = List<String>.from(client.imageDomainList);
    }

    @override
    void dispose()
    {
        _tab.dispose();
        _testSub?.cancel();
        super.dispose();
    }

    JmClient get _client => ref.read(jmClientProvider);

    // ===== 操作 =====

    /// 应用更改（同步到 client + 持久化）
    Future<void> _apply() async
    {
        _client.setApiDomainList(_apiList);
        _client.setImageDomainList(_imageList);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('已应用并保存到磁盘'),
                duration: Duration(seconds: 2),
            ),
        );
    }

    /// 从远程获取最新域名
    Future<void> _refreshLatest() async
    {
        setState(() => _refreshing = true);
        try
        {
            await _client.updateApiDomains(forceReload: true);
            if (!mounted) return;
            final api = JmDomainCache.latestApiList ?? const <String>[];
            final img = JmDomainCache.latestImageList ?? const <String>[];
            if (api.isNotEmpty)
            {
                setState(() => _apiList = List<String>.from(api));
            }
            if (img.isNotEmpty)
            {
                setState(() => _imageList = List<String>.from(img));
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        '已获取最新域名 (API: ${api.length}, 图片: ${img.length})',
                    ),
                ),
            );
        }
        catch (e)
        {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('获取失败: $e')),
            );
        }
        finally
        {
            if (mounted) setState(() => _refreshing = false);
        }
    }

    /// 测试当前 Tab 的所有域名（流式）
    Future<void> _testCurrentTab() async
    {
        final isApi = _tab.index == 0;
        final list = isApi ? _apiList : _imageList;
        if (list.isEmpty)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('列表为空')),
            );
            return;
        }
        // 取消旧订阅
        await _testSub?.cancel();
        setState(() {
            _testing = true;
            _testProgress = 0;
            _testTotal = list.length;
            final results = isApi ? _apiTestResults : _imageTestResults;
            results.clear();
        });

        final stream = isApi
            ? _client.testAllApiDomains()
            : _client.testAllImageDomains();
        final healthMap = isApi ? _apiHealth : _imageHealth;
        final results = isApi ? _apiTestResults : _imageTestResults;

        _testSub = stream.listen(
            (result)
            {
                if (!mounted) return;
                setState(() {
                    results[result.domain] = result;
                    _testProgress =
                        results.length / _testTotal;
                    // 累积健康历史
                    final h = healthMap[result.domain] ?? DomainHealth.empty;
                    healthMap[result.domain] = h.add(result.isSuccess);
                });
            },
            onError: (e)
            {
                if (!mounted) return;
                setState(() {
                    _testing = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('测速失败: $e')),
                );
            },
            onDone: ()
            {
                if (!mounted) return;
                setState(() {
                    _testing = false;
                    _testProgress = 1.0;
                });
            },
        );
    }

    /// 取消正在进行的测速
    void _cancelTest()
    {
        _testSub?.cancel();
        setState(() {
            _testing = false;
        });
    }

    /// 随机打乱当前 Tab 的域名
    void _shuffleCurrentTab()
    {
        final isApi = _tab.index == 0;
        setState(() {
            final list = isApi ? _apiList : _imageList;
            list.shuffle();
        });
    }

    /// 把当前 Tab 恢复为硬编码默认
    void _resetCurrentTabToDefault()
    {
        final isApi = _tab.index == 0;
        setState(() {
            if (isApi)
            {
                _apiList = List<String>.from(JmConfig.domainApiList);
                _apiTestResults.clear();
            }
            else
            {
                _imageList = List<String>.from(JmConfig.domainImageList);
                _imageTestResults.clear();
            }
        });
        // 持久化层也清除
        if (isApi)
        {
            _client.resetApiDomainsToDefault();
        }
        else
        {
            _client.resetImageDomainsToDefault();
        }
    }

    /// 按测速结果排序（快 -> 慢，失败排最后）
    void _sortCurrentTabBySpeed()
    {
        final isApi = _tab.index == 0;
        final results = isApi ? _apiTestResults : _imageTestResults;
        if (results.isEmpty)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先测试所有域名')),
            );
            return;
        }
        setState(() {
            final list = isApi ? _apiList : _imageList;
            list.sort((a, b)
            {
                final ra = results[a];
                final rb = results[b];
                if (ra == null && rb == null) return 0;
                if (ra == null) return 1;
                if (rb == null) return -1;
                if (ra.isSuccess && !rb.isSuccess) return -1;
                if (!ra.isSuccess && rb.isSuccess) return 1;
                return (ra.latencyMs ?? 0).compareTo(rb.latencyMs ?? 0);
            });
        });
    }

    /// 清空健康历史
    void _clearHealth()
    {
        final isApi = _tab.index == 0;
        setState(() {
            if (isApi)
            {
                _apiHealth.clear();
            }
            else
            {
                _imageHealth.clear();
            }
        });
    }

    /// 添加自定义域名
    Future<void> _addCustomDomain() async
    {
        final isApi = _tab.index == 0;
        final controller = TextEditingController();
        final result = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
                title: Text('添加${isApi ? 'API' : '图片'}域名'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: '例如 cdn-msp.jmapiproxy1.cc',
                    ),
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                    ),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                        child: const Text('添加'),
                    ),
                ],
            ),
        );
        if (result == null || result.isEmpty) return;
        if (!mounted) return;
        setState(() {
            if (isApi)
            {
                if (!_apiList.contains(result)) _apiList.add(result);
            }
            else
            {
                if (!_imageList.contains(result)) _imageList.add(result);
            }
        });
    }

    /// 上下移条目（onReorderItem 已自动处理 newIndex 调整，无需手动 -1）
    void _moveItem(int oldIndex, int newIndex)
    {
        final isApi = _tab.index == 0;
        setState(() {
            final list = isApi ? _apiList : _imageList;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
        });
    }

    /// 删除条目
    void _deleteItem(int index)
    {
        final isApi = _tab.index == 0;
        setState(() {
            final list = isApi ? _apiList : _imageList;
            list.removeAt(index);
        });
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(
                title: const Text('域名管理'),
                actions: [
                    IconButton(
                        tooltip: '应用更改',
                        icon: const Icon(Icons.check),
                        onPressed: _apply,
                    ),
                ],
                bottom: TabBar(
                    controller: _tab,
                    indicatorColor: AppColors.accent,
                    labelColor: AppColors.accent,
                    unselectedLabelColor: AppColors.textSecondary,
                    onTap: (_) => setState(() {}),
                    tabs: const [
                        Tab(text: 'API 域名'),
                        Tab(text: '图片域名'),
                    ],
                ),
            ),
            body: Column(
                children: [
                    // ===== 顶部操作栏 =====
                    _buildActionBar(),
                    // ===== 测速进度条 =====
                    if (_testing) _buildProgressBar(),
                    const Divider(height: 1, color: AppColors.divider),
                    // ===== 列表 =====
                    Expanded(
                        child: TabBarView(
                            controller: _tab,
                            children: [
                                _buildDomainList(
                                    list: _apiList,
                                    results: _apiTestResults,
                                    health: _apiHealth,
                                    onReorder: _moveItem,
                                    onDelete: _deleteItem,
                                ),
                                _buildDomainList(
                                    list: _imageList,
                                    results: _imageTestResults,
                                    health: _imageHealth,
                                    onReorder: _moveItem,
                                    onDelete: _deleteItem,
                                ),
                            ],
                        ),
                    ),
                ],
            ),
        );
    }

    /// 顶部操作栏（横向滚动避免溢出）
    Widget _buildActionBar()
    {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
                children: [
                    _actionButton(
                        icon: Icons.cloud_download_outlined,
                        label: '获取最新',
                        onTap: _refreshing ? null : _refreshLatest,
                        loading: _refreshing,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.speed_outlined,
                        label: '测试全部',
                        onTap: _testing ? null : _testCurrentTab,
                        loading: _testing,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.shuffle,
                        label: '随机打乱',
                        onTap: _shuffleCurrentTab,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.sort,
                        label: '按速度排序',
                        onTap: _sortCurrentTabBySpeed,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.history_toggle_off,
                        label: '清空历史',
                        onTap: _clearHealth,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.restore,
                        label: '恢复默认',
                        onTap: _resetCurrentTabToDefault,
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                        icon: Icons.add,
                        label: '添加域名',
                        onTap: _addCustomDomain,
                    ),
                ],
            ),
        );
    }

    /// 测速进度条
    Widget _buildProgressBar()
    {
        final completed = (_testProgress * _testTotal).round();
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceVariant,
            child: Row(
                children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                        ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    '测速中 $completed/$_testTotal',
                                    style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                    value: _testProgress,
                                    backgroundColor: AppColors.surface,
                                    color: AppColors.accent,
                                    minHeight: 3,
                                ),
                            ],
                        ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.textDisabled,
                        onPressed: _cancelTest,
                        visualDensity: VisualDensity.compact,
                    ),
                ],
            ),
        );
    }

    Widget _actionButton({
        required IconData icon,
        required String label,
        required VoidCallback? onTap,
        bool loading = false,
    })
    {
        return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        if (loading)
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                ),
                            )
                        else
                            Icon(icon, size: 16, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(label, style: const TextStyle(fontSize: 12)),
                    ],
                ),
            ),
        );
    }

    /// 域名列表
    Widget _buildDomainList({
        required List<String> list,
        required Map<String, DomainTestResult> results,
        required Map<String, DomainHealth> health,
        required void Function(int oldIndex, int newIndex) onReorder,
        required void Function(int index) onDelete,
    })
    {
        if (list.isEmpty)
        {
            return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        const Icon(Icons.dns_outlined,
                            size: 64, color: AppColors.textDisabled),
                        const SizedBox(height: 8),
                        const Text('列表为空',
                            style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                            onPressed: _addCustomDomain,
                            icon: const Icon(Icons.add),
                            label: const Text('添加域名'),
                        ),
                    ],
                ),
            );
        }
        return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: list.length,
            onReorderItem: onReorder,
            itemBuilder: (context, index)
            {
                final domain = list[index];
                final result = results[domain];
                final h = health[domain] ?? DomainHealth.empty;
                return _DomainTile(
                    key: ValueKey('${_tab.index}_$domain'),
                    index: index,
                    domain: domain,
                    result: result,
                    health: h,
                    onDelete: () => onDelete(index),
                );
            },
        );
    }
}

/// 单个域名行
class _DomainTile extends StatelessWidget
{
    final int index;
    final String domain;
    final DomainTestResult? result;
    final DomainHealth health;
    final VoidCallback onDelete;

    const _DomainTile({
        super.key,
        required this.index,
        required this.domain,
        required this.result,
        required this.health,
        required this.onDelete,
    });

    Color _speedColor()
    {
        if (result == null) return AppColors.textDisabled;
        switch (result!.speedLevel)
        {
            case 0: return AppColors.success;
            case 1: return AppColors.accentLight;
            case 2: return AppColors.warning;
            default: return AppColors.error;
        }
    }

    Color _healthColor()
    {
        switch (health.healthLevel)
        {
            case 0: return AppColors.success;
            case 1: return AppColors.accentLight;
            case 2: return AppColors.warning;
            default: return AppColors.textDisabled;
        }
    }

    @override
    Widget build(BuildContext context)
    {
        final speedColor = _speedColor();
        final healthColor = _healthColor();
        return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: result == null
                        ? AppColors.divider
                        : speedColor.withValues(alpha: 0.4),
                    width: 1,
                ),
            ),
            child: Row(
                children: [
                    // 拖拽手柄
                    ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                                Icons.drag_indicator,
                                color: AppColors.textDisabled,
                                size: 20,
                            ),
                        ),
                    ),
                    // 序号
                    Container(
                        width: 22,
                        alignment: Alignment.center,
                        child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                            ),
                        ),
                    ),
                    // 域名 + 副信息
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text(
                                    domain,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                ),
                                // 健康历史 + HTTP 状态
                                Row(
                                    children: [
                                        if (result != null && result!.isSuccess
                                            && result!.statusCode != null) ...[
                                            Text(
                                                'HTTP ${result!.statusCode}',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.textDisabled,
                                                ),
                                            ),
                                            const SizedBox(width: 8),
                                        ],
                                        if (health.totalTests > 0) ...[
                                            Icon(
                                                Icons.favorite,
                                                size: 10,
                                                color: healthColor,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                                health.displayHealth,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: healthColor,
                                                ),
                                            ),
                                        ],
                                    ],
                                ),
                                if (result != null && !result!.isSuccess)
                                    Text(
                                        '错误: ${result!.error}',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.error,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                    ),
                            ],
                        ),
                    ),
                    // 测速标签
                    if (result != null)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3,
                            ),
                            decoration: BoxDecoration(
                                color: speedColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                                result!.displayLatency,
                                style: TextStyle(
                                    color: speedColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                ),
                            ),
                        ),
                    // 删除
                    IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.textDisabled, size: 20),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                    ),
                ],
            ),
        );
    }
}
