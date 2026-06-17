import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/common/app_logger.dart';

/// 应用入口
void main()
{
    WidgetsFlutterBinding.ensureInitialized();

    // 锁定竖屏方向
    SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
    ]);

    // 触发 appLogger 单例初始化（同步创建 STARTED.txt 和 jmcomic-YYYYMMDD.log）
    appLogger.i('app started');

    runApp(
        const ProviderScope(
            child: App(),
        ),
    );
}
