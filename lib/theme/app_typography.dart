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
    static TextStyle heading1(BuildContext context) => TextStyle(
        fontFamily: headingFont,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.3,
        color: context.appColors.textPrimary,
    );

    /// 中标题
    static TextStyle heading2(BuildContext context) => TextStyle(
        fontFamily: headingFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: context.appColors.textPrimary,
    );

    /// 小标题
    static TextStyle heading3(BuildContext context) => TextStyle(
        fontFamily: headingFont,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: context.appColors.textPrimary,
    );

    /// 大正文
    static TextStyle bodyLarge(BuildContext context) => TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        height: 1.5,
        color: context.appColors.textPrimary,
    );

    /// 中正文
    static TextStyle bodyMedium(BuildContext context) => TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        height: 1.5,
        color: context.appColors.textPrimary,
    );

    /// 小正文
    static TextStyle bodySmall(BuildContext context) => TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        height: 1.4,
        color: context.appColors.textSecondary,
    );

    /// 说明文字
    static TextStyle caption(BuildContext context) => TextStyle(
        fontFamily: bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.normal,
        height: 1.4,
        color: context.appColors.textDisabled,
    );

    /// 按钮文字
    static TextStyle button(BuildContext context) => TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: context.appColors.background,
    );

    // 私有构造函数
    AppTypography._();
}
