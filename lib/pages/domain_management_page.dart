import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_config.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import 'domain_action_bar.dart';
import 'domain_health.dart';
import 'domain_test_progress.dart';
import 'domain_tile.dart';

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
                    DomainActionBar(
                        refreshing: _refreshing,
                        testing: _testing,
                        onRefreshLatest: _refreshLatest,
                        onTestAll: _testCurrentTab,
                        onShuffle: _shuffleCurrentTab,
                        onSortBySpeed: _sortCurrentTabBySpeed,
                        onClearHealth: _clearHealth,
                        onResetDefault: _resetCurrentTabToDefault,
                        onAddDomain: _addCustomDomain,
                    ),
                    // ===== 测速进度条 =====
                    DomainTestProgress(
                        testing: _testing,
                        progress: _testProgress,
                        total: _testTotal,
                        onCancel: _cancelTest,
                    ),
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
                return DomainTile(
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
