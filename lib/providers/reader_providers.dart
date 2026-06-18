import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/reader/network_monitor.dart';
import '../core/reader/reader_download_engine.dart';
import '../core/reader/reader_image_loader.dart';
import '../core/reader/smart_download_service.dart';
import '../data/database/task_dao.dart';
import 'config_provider.dart';
import 'search_provider.dart';

/// 网络状态监测器 Provider（全局单例）
final networkMonitorProvider = Provider<NetworkMonitor>((ref)
{
    final monitor = NetworkMonitor();
    monitor.init();
    ref.onDispose(monitor.dispose);
    return monitor;
});

/// 多线程阅读下载引擎 Provider
/// 用于在线阅读当前页/预加载页的即时加载
final readerDownloadEngineProvider = Provider<ReaderDownloadEngine>((ref)
{
    final client = ref.watch(jmClientProvider);
    final configState = ref.watch(configProvider);
    final config = configState.config;
    final monitor = ref.watch(networkMonitorProvider);

    final engine = ReaderDownloadEngine(
        client: client,
        networkMonitor: monitor,
        concurrency: config.imageThreadCount.clamp(1, 10),
    );

    ref.onDispose(engine.dispose);
    return engine;
});

/// 阅读图片加载器 Provider
/// 统一加载入口：内存缓存 → 临时解密缓存 → 网络下载
final readerImageLoaderProvider = Provider<ReaderImageLoader>((ref)
{
    final engine = ref.watch(readerDownloadEngineProvider);
    return ReaderImageLoader(engine: engine);
});

/// 智能下载服务 Provider
/// 在线阅读时自动将整个章节以标准下载格式保存到本地
final smartDownloadServiceProvider = Provider<SmartDownloadService>((ref)
{
    final client = ref.watch(jmClientProvider);
    final taskDao = ref.watch(taskDaoProvider);
    final configState = ref.watch(configProvider);
    final config = configState.config;
    final monitor = ref.watch(networkMonitorProvider);

    final service = SmartDownloadService(
        client: client,
        taskDao: taskDao,
        downloadDir: '',
        networkMonitor: monitor,
        imageThreadCount: config.imageThreadCount.clamp(1, 10),
    );

    ref.onDispose(service.dispose);
    return service;
});

/// 任务 DAO Provider
final taskDaoProvider = Provider<TaskDao>((ref)
{
    return TaskDao();
});
