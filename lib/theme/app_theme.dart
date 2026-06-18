import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// 应用主题定义
class AppTheme
{
    /// 深色主题（默认）
    static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        scheme: AppColorsScheme.dark,
        systemOverlayStyle: SystemUiOverlayStyle.light,
    );

    /// 浅色主题
    static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        scheme: AppColorsScheme.light,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
    );

    /// 构建主题（dark / light 共用结构）
    static ThemeData _buildTheme({
        required Brightness brightness,
        required AppColorsScheme scheme,
        required SystemUiOverlayStyle systemOverlayStyle,
    })
    {
        final isDark = brightness == Brightness.dark;
        return ThemeData(
            brightness: brightness,
            scaffoldBackgroundColor: scheme.background,
            // 关键：把自定义颜色挂到 ThemeData.extensions，让 context.appColors 可用
            extensions: <ThemeExtension<dynamic>>[scheme],
            colorScheme: ColorScheme(
                brightness: brightness,
                primary: scheme.accent,
                secondary: scheme.accentLight,
                surface: scheme.surface,
                error: scheme.error,
                onPrimary: isDark ? scheme.background : scheme.surface,
                onSecondary: isDark ? scheme.background : scheme.surface,
                onSurface: scheme.textPrimary,
                onError: scheme.surface,
            ),
            appBarTheme: AppBarTheme(
                backgroundColor: scheme.background,
                elevation: 0,
                centerTitle: true,
                systemOverlayStyle: systemOverlayStyle,
                titleTextStyle: TextStyle(
                    fontFamily: 'NotoSerifSC',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.textPrimary,
                ),
                iconTheme: IconThemeData(color: scheme.textPrimary),
            ),
            cardTheme: CardThemeData(
                color: scheme.surface,
                elevation: 2,
                shadowColor: scheme.shadow,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                ),
            ),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: scheme.surface,
                indicatorColor: scheme.accent.withValues(alpha: 0.3),
                iconTheme: WidgetStateProperty.resolveWith((states)
                {
                    if (states.contains(WidgetState.selected))
                    {
                        return IconThemeData(color: scheme.accent);
                    }
                    return IconThemeData(color: scheme.textSecondary);
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states)
                {
                    if (states.contains(WidgetState.selected))
                    {
                        return TextStyle(fontSize: 12, color: scheme.accent);
                    }
                    return TextStyle(fontSize: 12, color: scheme.textSecondary);
                }),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.accent,
                    foregroundColor: scheme.background,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                    ),
                ),
            ),
            textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                    foregroundColor: scheme.accent,
                ),
            ),
            inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: scheme.surfaceVariant,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.accent, width: 2),
                ),
                hintStyle: TextStyle(color: scheme.textDisabled),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                ),
            ),
            dividerTheme: DividerThemeData(
                color: scheme.divider,
                thickness: 1,
                space: 1,
            ),
            chipTheme: ChipThemeData(
                backgroundColor: scheme.surfaceVariant,
                selectedColor: scheme.accent,
                labelStyle: TextStyle(color: scheme.textPrimary),
                secondaryLabelStyle: TextStyle(color: scheme.background),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                ),
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
                color: scheme.accent,
                linearTrackColor: scheme.surfaceVariant,
            ),
            snackBarTheme: SnackBarThemeData(
                backgroundColor: scheme.surface,
                contentTextStyle: TextStyle(color: scheme.textPrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                ),
                behavior: SnackBarBehavior.floating,
            ),
            dialogTheme: DialogThemeData(
                backgroundColor: scheme.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                ),
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
                },
            ),
        );
    }

    // 私有构造函数
    AppTheme._();
}
