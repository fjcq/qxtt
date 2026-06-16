import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 分类标签组件
class CategoryChip extends StatelessWidget
{
    /// 标签文本
    final String label;

    /// 是否选中
    final bool isSelected;

    /// 点击回调
    final VoidCallback? onTap;

    const CategoryChip({
        super.key,
        required this.label,
        this.isSelected = false,
        this.onTap,
    });

    @override
    Widget build(BuildContext context)
    {
        return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                ),
                decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? Border.all(color: AppColors.accentLight, width: 1)
                        : null,
                ),
                child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? AppColors.background
                            : AppColors.textSecondary,
                    ),
                ),
            ),
        );
    }
}
