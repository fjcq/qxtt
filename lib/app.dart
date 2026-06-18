import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/config_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// 应用根组件
///
/// 主题模式由 [configProvider] 中的 `themeMode` 决定：
///   - `dark`：强制深色
///   - `light`：强制浅色
///   - `system`：跟随系统
class App extends ConsumerWidget
{
    const App({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        try
        {
            final router = ref.watch(routerProvider);
            final themeMode = ref.watch(
                configProvider.select((s) => s.config.themeMode),
            );
            final flutterThemeMode = _toFlutterThemeMode(themeMode);

            return MaterialApp.router(
                title: '七星天堂',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: flutterThemeMode,
                routerConfig: router,
            );
        }
        catch (e, stack)
        {
            debugPrint('=== App Build Error ===');
            debugPrint(e.toString());
            debugPrint(stack.toString());
            return MaterialApp(
                home: Scaffold(
                    body: Center(child: Text('Error: $e')),
                ),
            );
        }
    }

    /// 将配置中的 `themeMode` 字符串映射到 Flutter 的 [ThemeMode] 枚举
    static ThemeMode _toFlutterThemeMode(String mode)
    {
        switch (mode)
        {
            case 'light':
                return ThemeMode.light;
            case 'system':
                return ThemeMode.system;
            case 'dark':
            default:
                return ThemeMode.dark;
        }
    }
}
