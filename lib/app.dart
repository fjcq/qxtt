import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

/// 应用根组件
class App extends ConsumerWidget
{
    const App({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        try
        {
            final router = ref.watch(routerProvider);

            return MaterialApp.router(
                title: 'JMComic',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.darkTheme,
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
}
