import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/common/app_logger.dart';
import 'providers/auth_provider.dart';
import 'providers/config_provider.dart';
import 'utils/library_storage.dart';

/// 应用入口
Future<void> main() async
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

    // 使用显式 ProviderContainer 以便启动时主动初始化部分 Provider：
    // 1. 先等待磁盘配置加载完成，保证首页挂载时 jmClientProvider 首建即为
    //    最终配置（含代理），避免配置异步就绪后重建客户端导致首页首次
    //    加载结果被丢弃（表现为启动后首页空白，点击分类才有数据）
    // 2. authProvider 是懒加载的，若只在设置页/收藏页被 watch，
    //    启动后直接进详情页收藏会误判为未登录，故在此触发会话恢复
    final container = ProviderContainer();
    await container.read(configProvider.notifier).initialized;
    container.read(authProvider);

    runApp(
        UncontrolledProviderScope(
            container: container,
            child: const App(),
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
