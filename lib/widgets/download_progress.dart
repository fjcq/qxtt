import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 下载进度条组件
class DownloadProgress extends StatelessWidget
{
    /// 进度值 0.0 ~ 1.0
    final double progress;

    /// 状态文本
    final String statusText;

    /// 当前/总数 文本
    final String countText;

    const DownloadProgress({
        super.key,
        required this.progress,
        this.statusText = '',
        this.countText = '',
    });

    @override
    Widget build(BuildContext context)
    {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // 状态和计数行
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        Text(
                            statusText,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                            ),
                        ),
                        Text(
                            countText,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                            ),
                        ),
                    ],
                ),
                const SizedBox(height: 6),
                // 进度条
                ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? AppColors.success
                                : AppColors.accent,
                        ),
                    ),
                ),
            ],
        );
    }
}
