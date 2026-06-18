import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_service.dart';
import '../data/database/task_dao.dart';
import '../data/models/download_task_model.dart';
import 'download_state.dart';

/// 下载 Notifier 基类
/// 抽取公共依赖，供调度 mixin 复用
abstract class DownloadNotifierBase extends StateNotifier<DownloadState>
{
    /// 任务数据库访问对象
    final TaskDao taskDao;

    /// 下载服务
    final DownloadService downloadService;

    /// Riverpod Ref
    final Ref ref;

    /// 下载进度流订阅
    StreamSubscription? progressSub;

    /// 已调度自动归档的任务 ID（防止重复调度）
    final Set<String> scheduledArchives = {};

    /// 已完成的相册任务（用于历史补全到 library）
    final List<DownloadTaskModel> historicalCompleted = [];

    /// 构造基类
    DownloadNotifierBase(this.ref, this.taskDao, this.downloadService)
        : super(const DownloadState());

    /// 加载所有任务（由子类实现）
    Future<void> loadTasks();
}
