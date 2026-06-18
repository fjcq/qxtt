import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 域名测速进度条
class DomainTestProgress extends StatelessWidget
{
    final bool testing;
    final double progress;
    final int total;
    final VoidCallback onCancel;

    const DomainTestProgress({
        super.key,
        required this.testing,
        required this.progress,
        required this.total,
        required this.onCancel,
    });

    @override
    Widget build(BuildContext context)
    {
        if (!testing) return const SizedBox.shrink();
        final completed = (progress * total).round();
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: context.appColors.surfaceVariant,
            child: Row(
                children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.appColors.accent,
                        ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    '测速中 $completed/$total',
                                    style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: context.appColors.surface,
                                    color: context.appColors.accent,
                                    minHeight: 3,
                                ),
                            ],
                        ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: context.appColors.textDisabled,
                        onPressed: onCancel,
                        visualDensity: VisualDensity.compact,
                    ),
                ],
            ),
        );
    }
}
