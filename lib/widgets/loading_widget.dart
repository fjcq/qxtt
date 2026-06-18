import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 加载中组件
class LoadingWidget extends StatelessWidget
{
    /// 提示文字
    final String message;

    const LoadingWidget({
        super.key,
        this.message = '加载中...',
    });

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    CircularProgressIndicator(
                        color: context.appColors.accent,
                        strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                        message,
                        style: TextStyle(
                            color: context.appColors.textSecondary,
                            fontSize: 14,
                        ),
                    ),
                ],
            ),
        );
    }
}
