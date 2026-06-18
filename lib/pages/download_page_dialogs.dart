import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 通用确认弹窗
Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool danger = false,
}) async
{
    final result = await showDialog<bool>(
        context: context,
        builder: (ctx)
        {
            return AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                ),
                title: Text(title,
                    style: const TextStyle(color: AppColors.textPrimary)),
                content: Text(message,
                    style: const TextStyle(color: AppColors.textSecondary)),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(cancelText,
                            style: const TextStyle(color: AppColors.textSecondary)),
                    ),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                            confirmText,
                            style: TextStyle(
                                color: danger
                                    ? AppColors.error
                                    : AppColors.accent,
                                fontWeight: FontWeight.w600,
                            ),
                        ),
                    ),
                ],
            );
        },
    );
    return result ?? false;
}
