import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 应用字体排版
class AppTypography
{
    /// 标题字体
    static const String headingFont = 'NotoSerifSC';

    /// 正文字体
    static const String bodyFont = 'NotoSansSC';

    /// 大标题
    static const TextStyle heading1 = TextStyle(
        fontFamily: headingFont,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.3,
        color: AppColors.textPrimary,
    );

    /// 中标题
    static const TextStyle heading2 = TextStyle(
        fontFamily: headingFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.textPrimary,
    );

    /// 小标题
    static const TextStyle heading3 = TextStyle(
        fontFamily: headingFont,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.textPrimary,
    );

    /// 大正文
    static const TextStyle bodyLarge = TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        height: 1.5,
        color: AppColors.textPrimary,
    );

    /// 中正文
    static const TextStyle bodyMedium = TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        height: 1.5,
        color: AppColors.textPrimary,
    );

    /// 小正文
    static const TextStyle bodySmall = TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        height: 1.4,
        color: AppColors.textSecondary,
    );

    /// 说明文字
    static const TextStyle caption = TextStyle(
        fontFamily: bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.normal,
        height: 1.4,
        color: AppColors.textDisabled,
    );

    /// 按钮文字
    static const TextStyle button = TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: AppColors.background,
    );

    // 私有构造函数
    AppTypography._();
}
