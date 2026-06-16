import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// 应用主题定义
class AppTheme
{
    /// 深色主题（默认）
    static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            secondary: AppColors.accentLight,
            surface: AppColors.surface,
            error: AppColors.error,
            onPrimary: AppColors.background,
            onSecondary: AppColors.background,
            onSurface: AppColors.textPrimary,
            onError: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            titleTextStyle: TextStyle(
                fontFamily: 'NotoSerifSC',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
            ),
            iconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
        cardTheme: CardThemeData(
            color: AppColors.surface,
            elevation: 2,
            shadowColor: AppColors.shadow,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
            ),
        ),
        navigationBarTheme: NavigationBarThemeData(
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.accent.withValues(alpha: 0.3),
            iconTheme: WidgetStateProperty.resolveWith((states)
            {
                if (states.contains(WidgetState.selected))
                {
                    return const IconThemeData(color: AppColors.accent);
                }
                return const IconThemeData(color: AppColors.textSecondary);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states)
            {
                if (states.contains(WidgetState.selected))
                {
                    return const TextStyle(fontSize: 12, color: AppColors.accent);
                }
                return const TextStyle(fontSize: 12, color: AppColors.textSecondary);
            }),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
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
                foregroundColor: AppColors.accent,
            ),
        ),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
            hintStyle: const TextStyle(color: AppColors.textDisabled),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
            ),
        ),
        dividerTheme: const DividerThemeData(
            color: AppColors.divider,
            thickness: 1,
            space: 1,
        ),
        chipTheme: ChipThemeData(
            backgroundColor: AppColors.surfaceVariant,
            selectedColor: AppColors.accent,
            labelStyle: const TextStyle(color: AppColors.textPrimary),
            secondaryLabelStyle: const TextStyle(color: AppColors.background),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
            ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: AppColors.accent,
            linearTrackColor: AppColors.surfaceVariant,
        ),
        snackBarTheme: SnackBarThemeData(
            backgroundColor: AppColors.surface,
            contentTextStyle: const TextStyle(color: AppColors.textPrimary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
            ),
            behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
            backgroundColor: AppColors.surface,
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

    // 私有构造函数
    AppTheme._();
}
