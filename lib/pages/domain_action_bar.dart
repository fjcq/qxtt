import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 域名管理页顶部操作栏
class DomainActionBar extends StatelessWidget
{
    final bool refreshing;
    final bool testing;
    final VoidCallback onRefreshLatest;
    final VoidCallback onTestAll;
    final VoidCallback onShuffle;
    final VoidCallback onSortBySpeed;
    final VoidCallback onClearHealth;
    final VoidCallback onResetDefault;
    final VoidCallback onAddDomain;

    const DomainActionBar({
        super.key,
        required this.refreshing,
        required this.testing,
        required this.onRefreshLatest,
        required this.onTestAll,
        required this.onShuffle,
        required this.onSortBySpeed,
        required this.onClearHealth,
        required this.onResetDefault,
        required this.onAddDomain,
    });

    @override
    Widget build(BuildContext context)
    {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
                children: [
                    _ActionButton(
                        icon: Icons.cloud_download_outlined,
                        label: '获取最新',
                        onTap: refreshing ? null : onRefreshLatest,
                        loading: refreshing,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.speed_outlined,
                        label: '测试全部',
                        onTap: testing ? null : onTestAll,
                        loading: testing,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.shuffle,
                        label: '随机打乱',
                        onTap: onShuffle,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.sort,
                        label: '按速度排序',
                        onTap: onSortBySpeed,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.history_toggle_off,
                        label: '清空历史',
                        onTap: onClearHealth,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.restore,
                        label: '恢复默认',
                        onTap: onResetDefault,
                    ),
                    const SizedBox(width: 6),
                    _ActionButton(
                        icon: Icons.add,
                        label: '添加域名',
                        onTap: onAddDomain,
                    ),
                ],
            ),
        );
    }
}

/// 单个操作按钮
class _ActionButton extends StatelessWidget
{
    final IconData icon;
    final String label;
    final VoidCallback? onTap;
    final bool loading;

    const _ActionButton({
        required this.icon,
        required this.label,
        required this.onTap,
        this.loading = false,
    });

    @override
    Widget build(BuildContext context)
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
}
