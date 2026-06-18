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

    /// 下载速度文本
    final String speedText;

    const DownloadProgress({
        super.key,
        required this.progress,
        this.statusText = '',
        this.countText = '',
        this.speedText = '',
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
                        Expanded(
                            child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.appColors.textSecondary,
                                ),
                            ),
                        ),
                        if (speedText.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                    speedText,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.appColors.accent,
                                        fontWeight: FontWeight.w500,
                                    ),
                                ),
                            ),
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                                countText,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.appColors.textSecondary,
                                ),
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
                        backgroundColor: context.appColors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? context.appColors.success
                                : context.appColors.accent,
                        ),
                    ),
                ),
            ],
        );
    }
}
