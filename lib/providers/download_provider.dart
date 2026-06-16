import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_service.dart';
import '../data/database/task_dao.dart';
import '../data/models/download_task_model.dart';
import 'search_provider.dart';

/// 下载管理状态
class DownloadState
{
    /// 所有下载任务
    final List<DownloadTaskModel> tasks;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    const DownloadState({
        this.tasks = const [],
        this.isLoading = false,
        this.error,
    });

    DownloadState copyWith({
        List<DownloadTaskModel>? tasks,
        bool? isLoading,
        String? error,
    })
    {
        return DownloadState(
            tasks: tasks ?? this.tasks,
            isLoading: isLoading ?? this.isLoading,
            error: error,
        );
    }
}

/// 下载管理 Provider
class DownloadNotifier extends StateNotifier<DownloadState>
{
    final TaskDao _taskDao;
    final DownloadService _downloadService;
    StreamSubscription? _progressSub;

    DownloadNotifier(this._taskDao, this._downloadService)
        : super(const DownloadState())
    {
        _init();
    }

    /// 初始化：加载任务和监听进度
    void _init()
    {
        _loadTasks();
        _progressSub = _downloadService.onProgress.listen((progress)
        {
            // 进度更新时刷新任务列表
            _loadTasks();
        });
    }

    /// 加载所有任务
    Future<void> _loadTasks() async
    {
        final tasks = await _taskDao.getAllTasks();
        state = state.copyWith(tasks: tasks);
    }

    /// 创建下载任务并开始下载
    Future<void> createAndStartDownload(
        String type,
        String jmId, {
        String? title,
    }) async
    {
        final task = await _downloadService.createTask(type, jmId, title: title);
        await _loadTasks();

        // 异步执行下载
        if (type == 'album')
        {
            _downloadService.downloadAlbum(task.taskId, jmId).then((_) => _loadTasks());
        }
        else
        {
            _downloadService.downloadPhoto(task.taskId, jmId).then((_) => _loadTasks());
        }
    }

    /// 取消下载任务
    Future<void> cancelTask(String taskId) async
    {
        _downloadService.cancelTask(taskId);
        await _taskDao.updateTaskStatus(taskId, 'cancelled', '已取消', 0.0);
        await _loadTasks();
    }

    /// 删除下载任务
    Future<void> deleteTask(String taskId) async
    {
        _downloadService.cancelTask(taskId);
        await _taskDao.deleteTask(taskId);
        await _loadTasks();
    }

    /// 清除已完成任务
    Future<void> clearCompleted() async
    {
        await _taskDao.clearCompletedTasks();
        await _loadTasks();
    }

    /// 刷新任务列表
    Future<void> refresh() async
    {
        await _loadTasks();
    }

    @override
    void dispose()
    {
        _progressSub?.cancel();
        _downloadService.dispose();
        super.dispose();
    }
}

/// 下载服务 Provider
final downloadServiceProvider = Provider<DownloadService>((ref)
{
    final client = ref.watch(jmClientProvider);
    final taskDao = ref.watch(taskDaoProvider);
    return DownloadService(
        client: client,
        taskDao: taskDao,
        downloadDir: '', // 将在初始化时设置
    );
});

/// 下载管理 Provider 实例
final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref)
{
    final taskDao = ref.watch(taskDaoProvider);
    final downloadService = ref.watch(downloadServiceProvider);
    return DownloadNotifier(taskDao, downloadService);
});
