import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/common/app_logger.dart';
import 'utils/library_storage.dart';

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

    // 【性能优化 P2】后台异步迁移旧版 .ok 标记到章节级 .complete
    // fire-and-forget，不阻塞应用启动
    unawaited(_migrateOkToComplete());

    runApp(
        const ProviderScope(
            child: App(),
        ),
    );
}

/// 后台迁移旧版 .ok 标记到 .complete
/// 扫描下载根目录下所有章节，将完整下载的章节合并为单个 .complete 文件
Future<void> _migrateOkToComplete() async
{
    try
    {
        final downloadRoot = await LibraryStorage.getDownloadDir();
        await ChapterCompleteHelper.migrateAllChapters(downloadRoot);
    }
    catch (e)
    {
        appLogger.e('迁移 .ok 到 .complete 失败: $e');
    }
}
