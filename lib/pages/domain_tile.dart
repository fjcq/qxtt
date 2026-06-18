import 'package:flutter/material.dart';

import '../core/jm/jm_client.dart';
import '../theme/app_colors.dart';
import 'domain_health.dart';

/// 单个域名行
class DomainTile extends StatelessWidget
{
    final int index;
    final String domain;
    final DomainTestResult? result;
    final DomainHealth health;
    final VoidCallback onDelete;

    const DomainTile({
        super.key,
        required this.index,
        required this.domain,
        required this.result,
        required this.health,
        required this.onDelete,
    });

    Color _speedColor(BuildContext context)
    {
        if (result == null) return context.appColors.textDisabled;
        switch (result!.speedLevel)
        {
            case 0: return context.appColors.success;
            case 1: return context.appColors.accentLight;
            case 2: return context.appColors.warning;
            default: return context.appColors.error;
        }
    }

    Color _healthColor(BuildContext context)
    {
        switch (health.healthLevel)
        {
            case 0: return context.appColors.success;
            case 1: return context.appColors.accentLight;
            case 2: return context.appColors.warning;
            default: return context.appColors.textDisabled;
        }
    }

    @override
    Widget build(BuildContext context)
    {
        final speedColor = _speedColor(context);
        final healthColor = _healthColor(context);
        return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: result == null
                        ? context.appColors.divider
                        : speedColor.withValues(alpha: 0.4),
                    width: 1,
                ),
            ),
            child: Row(
                children: [
                    // 拖拽手柄
                    ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                                Icons.drag_indicator,
                                color: context.appColors.textDisabled,
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
                            style: TextStyle(
                                color: context.appColors.textSecondary,
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
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: context.appColors.textDisabled,
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
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: context.appColors.error,
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
                        icon: Icon(Icons.delete_outline,
                            color: context.appColors.textDisabled, size: 20),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                    ),
                ],
            ),
        );
    }
}
