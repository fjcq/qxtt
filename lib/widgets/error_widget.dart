import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 错误提示组件
class AppErrorWidget extends StatelessWidget
{
    /// 错误信息
    final String message;

    /// 重试回调
    final VoidCallback? onRetry;

    const AppErrorWidget({
        super.key,
        required this.message,
        this.onRetry,
    });

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                        if (onRetry != null) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重试'),
                            ),
                        ],
                    ],
                ),
            ),
        );
    }
}
