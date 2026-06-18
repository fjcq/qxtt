import 'package:flutter/material.dart';

/// 应用色彩常量（暗色版，保留向后兼容）
///
/// 历史原因：全代码库大量以 `AppColors.background` 等 const 形式使用，
/// 这里保留原 API 不变。新代码应使用 `context.appColors.xxx` 获取当前主题色。
class AppColors
{
    /// 暗紫黑背景
    static const Color background = Color(0xFF0f0d15);

    /// 深紫表面
    static const Color surface = Color(0xFF1a1625);

    /// 表面变体（稍浅）
    static const Color surfaceVariant = Color(0xFF241f30);

    /// 琥珀金强调色
    static const Color accent = Color(0xFFf0a500);

    /// 浅金强调色
    static const Color accentLight = Color(0xFFffd166);

    /// 主文字色
    static const Color textPrimary = Color(0xFFf5f5f5);

    /// 次文字色
    static const Color textSecondary = Color(0xFF9ca3af);

    /// 禁用文字色
    static const Color textDisabled = Color(0xFF6b7280);

    /// 错误红
    static const Color error = Color(0xFFef4444);

    /// 成功绿
    static const Color success = Color(0xFF22c55e);

    /// 警告橙
    static const Color warning = Color(0xFFf97316);

    /// 信息蓝
    static const Color info = Color(0xFF3b82f6);

    /// 分割线
    static const Color divider = Color(0xFF2d2640);

    /// 卡片阴影
    static const Color shadow = Color(0x40000000);

    // 私有构造函数
    AppColors._();
}

/// 应用色彩常量（浅色版）
class AppColorsLight
{
    /// 米白背景
    static const Color background = Color(0xFFFAF9F6);

    /// 浅米表面
    static const Color surface = Color(0xFFFFFFFF);

    /// 表面变体（稍深）
    static const Color surfaceVariant = Color(0xFFF1EFE9);

    /// 琥珀金强调色（保持品牌色）
    static const Color accent = Color(0xFFd97706);

    /// 深琥珀强调色
    static const Color accentLight = Color(0xFFb45309);

    /// 主文字色（深色）
    static const Color textPrimary = Color(0xFF1f1d2b);

    /// 次文字色
    static const Color textSecondary = Color(0xFF6b6b7b);

    /// 禁用文字色
    static const Color textDisabled = Color(0xFFb0b0bc);

    /// 错误红
    static const Color error = Color(0xFFdc2626);

    /// 成功绿
    static const Color success = Color(0xFF16a34a);

    /// 警告橙
    static const Color warning = Color(0xFFea580c);

    /// 信息蓝
    static const Color info = Color(0xFF2563eb);

    /// 分割线
    static const Color divider = Color(0xFFE5E2DA);

    /// 卡片阴影
    static const Color shadow = Color(0x20000000);

    // 私有构造函数
    AppColorsLight._();
}

/// 当前主题色彩方案（通过 ThemeExtension 暴露给 ThemeData）
class AppColorsScheme extends ThemeExtension<AppColorsScheme>
{
    /// 背景
    final Color background;

    /// 表面
    final Color surface;

    /// 表面变体
    final Color surfaceVariant;

    /// 强调色
    final Color accent;

    /// 浅色强调
    final Color accentLight;

    /// 主文字
    final Color textPrimary;

    /// 次文字
    final Color textSecondary;

    /// 禁用文字
    final Color textDisabled;

    /// 错误
    final Color error;

    /// 成功
    final Color success;

    /// 警告
    final Color warning;

    /// 信息
    final Color info;

    /// 分割线
    final Color divider;

    /// 阴影
    final Color shadow;

    const AppColorsScheme({
        required this.background,
        required this.surface,
        required this.surfaceVariant,
        required this.accent,
        required this.accentLight,
        required this.textPrimary,
        required this.textSecondary,
        required this.textDisabled,
        required this.error,
        required this.success,
        required this.warning,
        required this.info,
        required this.divider,
        required this.shadow,
    });

    /// 暗色方案
    static const AppColorsScheme dark = AppColorsScheme(
        background: AppColors.background,
        surface: AppColors.surface,
        surfaceVariant: AppColors.surfaceVariant,
        accent: AppColors.accent,
        accentLight: AppColors.accentLight,
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        textDisabled: AppColors.textDisabled,
        error: AppColors.error,
        success: AppColors.success,
        warning: AppColors.warning,
        info: AppColors.info,
        divider: AppColors.divider,
        shadow: AppColors.shadow,
    );

    /// 浅色方案
    static const AppColorsScheme light = AppColorsScheme(
        background: AppColorsLight.background,
        surface: AppColorsLight.surface,
        surfaceVariant: AppColorsLight.surfaceVariant,
        accent: AppColorsLight.accent,
        accentLight: AppColorsLight.accentLight,
        textPrimary: AppColorsLight.textPrimary,
        textSecondary: AppColorsLight.textSecondary,
        textDisabled: AppColorsLight.textDisabled,
        error: AppColorsLight.error,
        success: AppColorsLight.success,
        warning: AppColorsLight.warning,
        info: AppColorsLight.info,
        divider: AppColorsLight.divider,
        shadow: AppColorsLight.shadow,
    );

    @override
    AppColorsScheme copyWith({
        Color? background,
        Color? surface,
        Color? surfaceVariant,
        Color? accent,
        Color? accentLight,
        Color? textPrimary,
        Color? textSecondary,
        Color? textDisabled,
        Color? error,
        Color? success,
        Color? warning,
        Color? info,
        Color? divider,
        Color? shadow,
    })
    {
        return AppColorsScheme(
            background: background ?? this.background,
            surface: surface ?? this.surface,
            surfaceVariant: surfaceVariant ?? this.surfaceVariant,
            accent: accent ?? this.accent,
            accentLight: accentLight ?? this.accentLight,
            textPrimary: textPrimary ?? this.textPrimary,
            textSecondary: textSecondary ?? this.textSecondary,
            textDisabled: textDisabled ?? this.textDisabled,
            error: error ?? this.error,
            success: success ?? this.success,
            warning: warning ?? this.warning,
            info: info ?? this.info,
            divider: divider ?? this.divider,
            shadow: shadow ?? this.shadow,
        );
    }

    @override
    AppColorsScheme lerp(ThemeExtension<AppColorsScheme>? other, double t)
    {
        if (other is! AppColorsScheme) return this;
        return AppColorsScheme(
            background: Color.lerp(background, other.background, t)!,
            surface: Color.lerp(surface, other.surface, t)!,
            surfaceVariant:
                Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
            accent: Color.lerp(accent, other.accent, t)!,
            accentLight: Color.lerp(accentLight, other.accentLight, t)!,
            textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
            textSecondary:
                Color.lerp(textSecondary, other.textSecondary, t)!,
            textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
            error: Color.lerp(error, other.error, t)!,
            success: Color.lerp(success, other.success, t)!,
            warning: Color.lerp(warning, other.warning, t)!,
            info: Color.lerp(info, other.info, t)!,
            divider: Color.lerp(divider, other.divider, t)!,
            shadow: Color.lerp(shadow, other.shadow, t)!,
        );
    }
}

/// 主题色彩方案快捷访问扩展
/// 用法：`context.appColors.background` 获取当前主题的背景色
extension AppColorsX on BuildContext
{
    AppColorsScheme get appColors =>
        Theme.of(this).extension<AppColorsScheme>()!;
}
