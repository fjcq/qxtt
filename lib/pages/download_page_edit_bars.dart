import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 已下载分页编辑模式底栏
class LibraryEditBar extends StatelessWidget
{
    final int count;
    final VoidCallback onDelete;

    const LibraryEditBar({
        super.key,
        required this.count,
        required this.onDelete,
    });

    @override
    Widget build(BuildContext context)
    {
        return SafeArea(
            top: false,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                    ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                    children: [
                        const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                            child: Text(
                                '删除将同时清理本地文件',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                ),
                            ),
                        ),
                        FilledButton.icon(
                            onPressed: count == 0 ? null : onDelete,
                            icon: const Icon(Icons.delete, size: 18),
                            label: Text('删除 ($count)'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error,
                                disabledBackgroundColor:
                                    AppColors.error.withValues(alpha: 0.3),
                                foregroundColor: Colors.white,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}

/// 下载中分页编辑模式底栏
class TaskEditBar extends StatelessWidget
{
    final int count;
    final VoidCallback onRetry;
    final VoidCallback onDelete;

    const TaskEditBar({
        super.key,
        required this.count,
        required this.onRetry,
        required this.onDelete,
    });

    @override
    Widget build(BuildContext context)
    {
        return SafeArea(
            top: false,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                    ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                    children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: count == 0 ? null : onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text('重试 ($count)'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                    side: BorderSide(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.5),
                                    ),
                                ),
                            ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: FilledButton.icon(
                                onPressed: count == 0 ? null : onDelete,
                                icon: const Icon(Icons.delete, size: 18),
                                label: Text('删除 ($count)'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    disabledBackgroundColor:
                                        AppColors.error.withValues(alpha: 0.3),
                                    foregroundColor: Colors.white,
                                ),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}
