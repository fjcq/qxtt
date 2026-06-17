import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_service.dart';
import '../data/database/task_dao.dart';
import '../data/models/download_task_model.dart';
import '../utils/library_storage.dart';
import 'search_provider.dart';
import 'config_provider.dart';
import 'library_provider.dart';

/// 下载任务状态分组
/// 已完成（completed）任务在 2 秒后自动从列表中移除，
/// 因此下载 Tab 上只展示 active 与 failed 两种分组
enum DownloadTaskGroup
{
    /// 正在下载（running + pending）
    active,

    /// 失败 / 取消
    failed,
}

/// 下载任务展示模型
/// 包装 [DownloadTaskModel]，附带派生的展示字段（状态分组、显示标题等）
class DownloadTaskView
{
    final DownloadTaskModel task;

    const DownloadTaskView(this.task);

    /// 任务显示标题
    String get displayTitle
    {
        final t = task.title;
        if (t != null && t.isNotEmpty) return t;
        return task.jmId;
    }

    /// 是否处于活动状态（运行中或等待中）
    bool get isActive => task.status == 'running' || task.status == 'pending';

    /// 是否失败或被取消
    bool get isFailed => task.status == 'failed' || task.status == 'cancelled';

    /// 是否可重试（failed / cancelled 任务可重试）
    bool get isRetryable => isFailed;

    /// 任务分组（completed 不参与分组，会被自动移除）
    DownloadTaskGroup get group
    {
        if (isActive) return DownloadTaskGroup.active;
        return DownloadTaskGroup.failed;
    }

    /// 是否为整本下载
    bool get isAlbumTask => task.taskType == 'album';
}

/// 下载管理状态
class DownloadState
{
    /// 所有下载任务（含短暂的 completed 任务）
    final List<DownloadTaskModel> tasks;

    /// 是否正在加载
    final bool isLoading;

    /// 错误信息
    final String? error;

    /// 最近一次完成的任务（用于 UI 弹 SnackBar）
    final DownloadTaskModel? lastCompletedTask;

    /// 完成事件序号，UI 用其差值判断是否要弹新 SnackBar
    final int completionCounter;

    const DownloadState({
        this.tasks = const [],
        this.isLoading = false,
        this.error,
        this.lastCompletedTask,
        this.completionCounter = 0,
    });

    /// 按状态分组
    /// 已完成任务不出现在分组中（由 UI 与状态隔离，避免视觉重复）
    Map<DownloadTaskGroup, List<DownloadTaskView>> get grouped
    {
        final map = <DownloadTaskGroup, List<DownloadTaskView>>{
            DownloadTaskGroup.active: [],
            DownloadTaskGroup.failed: [],
        };
        for (final t in tasks)
        {
            // completed 任务不进入任何分组（2 秒后会被自动归档）
            if (t.status == 'completed') continue;
            final v = DownloadTaskView(t);
            map[v.group]!.add(v);
        }
        return map;
    }

    /// 总计活动任务数
    int get activeCount
    {
        var n = 0;
        for (final t in tasks)
        {
            if (t.status == 'running' || t.status == 'pending') n++;
        }
        return n;
    }

    /// 总计失败 / 取消任务数
    int get failedCount
    {
        var n = 0;
        for (final t in tasks)
        {
            if (t.status == 'failed' || t.status == 'cancelled') n++;
        }
        return n;
    }

    DownloadState copyWith({
        List<DownloadTaskModel>? tasks,
        bool? isLoading,
        String? error,
        DownloadTaskModel? lastCompletedTask,
        int? completionCounter,
    })
    {
        return DownloadState(
            tasks: tasks ?? this.tasks,
            isLoading: isLoading ?? this.isLoading,
            error: error,
            lastCompletedTask: lastCompletedTask ?? this.lastCompletedTask,
            completionCounter: completionCounter ?? this.completionCounter,
        );
    }
}

/// 下载管理 Provider
/// 关键设计：
/// - 任务完成后 2 秒自动从列表与数据库中移除（不再出现在"下载中"Tab）
/// - 完成后 Library 接管已下载章节的所有权
/// - 删除 / 重试 / 取消操作默认清理本地文件
class DownloadNotifier extends StateNotifier<DownloadState>
{
    final TaskDao _taskDao;
    final DownloadService _downloadService;
    final Ref _ref;
    StreamSubscription? _progressSub;

    /// 已调度自动归档的任务 ID（防止重复调度）
    final Set<String> _scheduledArchives = {};

    /// 已完成的相册任务（用于历史补全到 library）
    final List<DownloadTaskModel> _historicalCompleted = [];

    DownloadNotifier(this._ref, this._taskDao, this._downloadService)
        : super(const DownloadState())
    {
        _init();
    }

    /// 初始化：加载任务、监听进度、补全历史完成的任务到 library
    void _init()
    {
        _loadTasks().then((_) => _syncCompletedTasksToLibrary());
        _progressSub = _downloadService.onProgress.listen((progress)
        {
            _updateTaskProgress(progress);
        });
    }

    /// 根据进度事件更新内存中的任务状态
    void _updateTaskProgress(DownloadProgressEvent progress)
    {
        // 找到要更新的任务
        DownloadTaskModel? targetTask;
        for (final t in state.tasks)
        {
            if (t.taskId == progress.taskId)
            {
                targetTask = t;
                break;
            }
        }

        // 任务不存在时尝试重新加载
        if (targetTask == null)
        {
            _loadTasks();
            return;
        }

        // 同步下载进度相关字段
        if (progress.downloadedPhotoIds.isNotEmpty)
        {
            targetTask.downloadedPhotoIds = progress.downloadedPhotoIds;
        }
        if (progress.status == 'completed')
        {
            if (progress.author.isNotEmpty) targetTask.coverAuthor = progress.author;
            if (progress.pageCount > 0) targetTask.coverPageCount = progress.pageCount;
            if (progress.episodeCount > 0) targetTask.coverEpisodeCount = progress.episodeCount;
            if (progress.localCoverPath.isNotEmpty)
            {
                targetTask.coverPath = progress.localCoverPath;
            }
            if (progress.localPath.isNotEmpty)
            {
                targetTask.localPath = progress.localPath;
            }
        }
        targetTask
            ..status = progress.status
            ..currentImage = progress.current > 0
                ? progress.current
                : targetTask.currentImage
            ..totalImages = progress.total > 0
                ? progress.total
                : targetTask.totalImages
            ..progress = progress.progress
            ..speed = progress.speed
            ..message = progress.message;

        // 触发 UI 刷新
        state = state.copyWith(tasks: List.of(state.tasks));

        // 下载完成时：更新 Library + 安排自动归档
        if (progress.status == 'completed')
        {
            _handleDownloadCompleted(targetTask);
            // 通知 UI 弹 SnackBar
            state = state.copyWith(
                lastCompletedTask: targetTask,
                completionCounter: state.completionCounter + 1,
            );
            _scheduleAutoArchive(targetTask.taskId);
        }
    }

    /// 处理下载完成事件：将对应章节标记为已下载到 library
    void _handleDownloadCompleted(DownloadTaskModel task)
    {
        if (task.albumId.isEmpty) return;
        if (task.downloadedPhotoIds.isEmpty) return;

        _ref.read(libraryProvider.notifier).markEpisodesDownloaded(
            task.albumId,
            task.downloadedPhotoIds,
            title: task.title,
            author: task.coverAuthor.isNotEmpty ? task.coverAuthor : null,
            coverPath: task.coverPath,
            localPath: task.localPath,
            pageCount: task.coverPageCount > 0 ? task.coverPageCount : null,
            episodeCount: task.coverEpisodeCount > 0 ? task.coverEpisodeCount : null,
        );
    }

    /// 安排一个延迟归档：N 秒后将任务从状态与数据库中移除
    /// 用于让用户短暂看到"已完成"状态，然后自动消失
    void _scheduleAutoArchive(String taskId)
    {
        if (_scheduledArchives.contains(taskId)) return;
        _scheduledArchives.add(taskId);
        Future.delayed(const Duration(seconds: 2), () async
        {
            _scheduledArchives.remove(taskId);
            if (!mounted) return;
            final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
            if (task == null) return;
            if (task.status != 'completed') return;
            await archiveTask(taskId);
        });
    }

    /// 归档任务：从状态与数据库中移除
    /// 注意：completed 任务对应的本地文件由 library 接管，不在此处删除
    Future<void> archiveTask(String taskId) async
    {
        // 乐观更新：先从状态移除
        final remain = state.tasks.where((t) => t.taskId != taskId).toList();
        state = state.copyWith(tasks: remain);

        // 同步从数据库删除
        try
        {
            await _taskDao.deleteTask(taskId);
        }
        catch (_)
        {
            // 忽略：状态已更新，DB 失败下次启动会重试
        }
    }

    /// 应用启动时，将历史已完成的 album 任务补全到 library
    /// 用于修复旧版本产生的"library 中没有该 album 但有完成任务"的状态
    Future<void> _syncCompletedTasksToLibrary() async
    {
        // 收集所有 completed 任务（不在 library 中）
        final tasks = List<DownloadTaskModel>.from(state.tasks);
        for (final task in tasks)
        {
            if (task.status != 'completed') continue;
            if (task.albumId.isEmpty) continue;
            if (task.downloadedPhotoIds.isEmpty) continue;

            final existing = await _ref
                .read(libraryProvider.notifier)
                .getDownloadedEpisodes(task.albumId);
            if (existing.isNotEmpty) continue;

            _historicalCompleted.add(task);
            _handleDownloadCompleted(task);
        }
    }

    /// 加载所有任务
    Future<void> _loadTasks() async
    {
        final tasks = await _taskDao.getAllTasks();
        state = state.copyWith(tasks: tasks);
    }

    /// 创建下载任务并开始下载
    /// 若存在未完成的同目标任务（pending/running），不会重复创建
    /// 返回 (taskId, isNewlyCreated)
    Future<({String taskId, bool isNewlyCreated})> createAndStartDownload(
        String type,
        String jmId, {
        String? title,
        String? albumId,
    }) async
    {
        final effectiveAlbumId = albumId ?? (type == 'album' ? jmId : '');
        final existing = _findActiveDuplicate(type, jmId, effectiveAlbumId);
        if (existing != null)
        {
            return (taskId: existing.taskId, isNewlyCreated: false);
        }

        final task = await _downloadService.createTask(
            type,
            jmId,
            title: title,
            albumId: albumId,
        );
        await _loadTasks();

        if (type == 'album')
        {
            _downloadService.downloadAlbum(task.taskId, jmId).then((_) => _loadTasks());
        }
        else
        {
            _downloadService.downloadPhoto(task.taskId, jmId).then((_) => _loadTasks());
        }

        return (taskId: task.taskId, isNewlyCreated: true);
    }

    /// 查找未完成（pending/running）的同目标下载任务
    DownloadTaskModel? _findActiveDuplicate(
        String type,
        String jmId,
        String albumId,
    )
    {
        const activeStatuses = {'pending', 'running'};
        for (final t in state.tasks)
        {
            if (!activeStatuses.contains(t.status)) continue;
            if (t.taskType != type) continue;
            if (type == 'album')
            {
                if (t.jmId == jmId) return t;
            }
            else
            {
                if (t.jmId == jmId && t.albumId == albumId) return t;
            }
        }
        return null;
    }

    /// 取消下载任务
    /// 不删除本地文件，让用户可以重试
    /// 若希望彻底清理，请使用 deleteTask
    Future<void> cancelTask(String taskId) async
    {
        _downloadService.cancelTask(taskId);
        await _taskDao.updateTaskStatus(taskId, 'cancelled', '已取消', 0.0);
        await _loadTasks();
    }

    /// 重试已失败的下载任务
    /// - 取消当前任务（如有运行）
    /// - 清理可能存在的本地部分文件，避免新旧数据混合
    /// - 重置状态为 pending 并重新下载
    Future<bool> retryTask(String taskId) async
    {
        final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task == null) return false;
        if (!DownloadTaskView(task).isRetryable) return false;
        // 取消可能的正在运行状态
        _downloadService.cancelTask(taskId);
        // 清理可能存在的本地部分文件
        await _cleanupTaskFiles(task);
        // 重置任务状态
        await _taskDao.updateTaskStatus(taskId, 'pending', '准备重试', 0.0);
        await _loadTasks();
        // 重新触发下载
        if (task.taskType == 'album')
        {
            _downloadService
                .downloadAlbum(task.taskId, task.jmId)
                .then((_) => _loadTasks());
        }
        else
        {
            _downloadService
                .downloadPhoto(task.taskId, task.jmId)
                .then((_) => _loadTasks());
        }
        return true;
    }

    /// 批量重试多个失败任务
    Future<int> retryTasks(Iterable<String> taskIds) async
    {
        var count = 0;
        for (final id in taskIds)
        {
            if (await retryTask(id)) count++;
        }
        return count;
    }

    /// 删除下载任务
    /// [deleteFiles] 是否同时删除本地文件（默认 true）
    /// - active 任务：会先取消下载，再删除文件
    /// - failed/cancelled 任务：直接删除记录与文件
    /// - completed 任务：通常已被自动归档，不应到达此处
    Future<void> deleteTask(
        String taskId, {
        bool deleteFiles = true,
    }) async
    {
        final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
        // 取消正在运行的任务
        _downloadService.cancelTask(taskId);
        // 乐观更新：先从状态移除
        final remain = state.tasks.where((t) => t.taskId != taskId).toList();
        state = state.copyWith(tasks: remain);
        // 取消自动归档（如果已调度）
        _scheduledArchives.remove(taskId);
        // 清理本地文件
        if (deleteFiles && task != null)
        {
            await _cleanupTaskFiles(task);
        }
        // 异步删除数据库记录
        try
        {
            await _taskDao.deleteTask(taskId);
        }
        catch (_)
        {
            // 失败时重新加载恢复
            await _loadTasks();
        }
    }

    /// 批量删除任务（默认删除文件）
    /// 返回 (总数, 失败数)
    Future<(int total, int failed)> deleteTasks(
        Iterable<String> taskIds, {
        bool deleteFiles = true,
    }) async
    {
        final idList = taskIds.toList();
        if (idList.isEmpty) return (0, 0);
        var failed = 0;
        for (final id in idList)
        {
            try
            {
                await deleteTask(id, deleteFiles: deleteFiles);
            }
            catch (_)
            {
                failed++;
            }
        }
        return (idList.length, failed);
    }

    /// 清除失败 / 取消的任务记录（同时清理本地部分文件）
    Future<int> clearFailed() async
    {
        final failedIds = state.tasks
            .where((t) => t.status == 'failed' || t.status == 'cancelled')
            .map((t) => t.taskId)
            .toList();
        if (failedIds.isEmpty) return 0;
        final remain = state.tasks
            .where((t) => t.status != 'failed' && t.status != 'cancelled')
            .toList();
        state = state.copyWith(tasks: remain);
        for (final id in failedIds)
        {
            try
            {
                await _taskDao.deleteTask(id);
            }
            catch (_)
            {
                // 忽略单条失败
            }
        }
        return failedIds.length;
    }

    /// 全部重试失败任务
    Future<int> retryAllFailed() async
    {
        final failedIds = state.tasks
            .where((t) => t.status == 'failed' || t.status == 'cancelled')
            .map((t) => t.taskId)
            .toList();
        return retryTasks(failedIds);
    }

    /// 全部取消活动任务
    Future<void> cancelAllActive() async
    {
        final activeIds = state.tasks
            .where((t) => t.status == 'running' || t.status == 'pending')
            .map((t) => t.taskId)
            .toList();
        for (final id in activeIds)
        {
            await cancelTask(id);
        }
    }

    /// 刷新任务列表
    Future<void> refresh() async
    {
        await _loadTasks();
    }

    /// 解析下载目录
    /// 1) 等待 ConfigNotifier 完成初始化（避免首帧拿到空 downloadDir）
    /// 2) 优先使用配置值，为空时回退到默认目录
    Future<String> _resolveDownloadDir() async
    {
        await _ref.read(configProvider.notifier).initialized;
        final configured = _ref.read(configProvider).config.downloadDir;
        return LibraryStorage.getDownloadDir(configured: configured);
    }

    /// 清理指定任务对应的本地文件
    /// - album 任务：尝试多个候选路径删除整本目录
    /// - photo 任务：删除 downloadDir/jmId 目录（如果存在）
    /// 所有删除都走 [LibraryStorage.forceDelete]，递归失败时会重试 +
    /// Windows rmdir 强删 + 逐文件删空，确保彻底清理
    Future<void> _cleanupTaskFiles(DownloadTaskModel task) async
    {
        try
        {
            final downloadDir = await _resolveDownloadDir();
            if (task.taskType == 'album')
            {
                // album 任务：尝试多个候选
                // 1) task.localPath（下载时记录的真实路径）
                // 2) downloadDir/sanitize(title)
                // 3) downloadDir/sanitize(albumId)
                // 4) coverPath 反推（兜底）
                final candidates = <String>{};
                if (task.localPath.isNotEmpty) candidates.add(task.localPath);
                if (task.title != null && task.title!.isNotEmpty)
                {
                    candidates.add(
                        '$downloadDir${Platform.pathSeparator}${_sanitize(task.title!)}',
                    );
                }
                if (task.albumId.isNotEmpty)
                {
                    candidates.add(
                        '$downloadDir${Platform.pathSeparator}${_sanitize(task.albumId)}',
                    );
                }
                // coverPath 父目录（最可靠的"权威位置"）
                if (task.coverPath != null && task.coverPath!.isNotEmpty)
                {
                    try
                    {
                        final coverFile = File(task.coverPath!);
                        if (await coverFile.exists())
                        {
                            candidates.add(coverFile.parent.path);
                            if (coverFile.parent.parent.path.isNotEmpty &&
                                coverFile.parent.parent.path !=
                                    coverFile.parent.path)
                            {
                                candidates.add(coverFile.parent.parent.path);
                            }
                        }
                    }
                    catch (_)
                    {
                        // ignore
                    }
                }
                for (final path in candidates)
                {
                    final dir = Directory(path);
                    if (!await dir.exists()) continue;
                    await LibraryStorage.forceDelete(dir);
                }
            }
            else
            {
                // photo 任务：本地路径为 downloadDir/photoId
                final photoDir = Directory(
                    '$downloadDir${Platform.pathSeparator}${task.jmId}',
                );
                if (await photoDir.exists())
                {
                    await LibraryStorage.forceDelete(photoDir);
                }
            }
        }
        catch (_)
        {
            // 文件清理失败不影响主流程
        }
    }

    /// 文件名清洗（与 PathHelper.sanitizeFileName 规则保持一致）
    String _sanitize(String name)
    {
        var result = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        result = result.trimRight();
        while (result.endsWith('.'))
        {
            result = result.substring(0, result.length - 1);
        }
        if (result.isEmpty) result = 'unnamed';
        return result;
    }

    @override
    void dispose()
    {
        _scheduledArchives.clear();
        _historicalCompleted.clear();
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
    final config = ref.watch(configProvider).config;
    final downloadDir = config.downloadDir;
    return DownloadService(
        client: client,
        taskDao: taskDao,
        downloadDir: downloadDir,
    );
});

/// 下载管理 Provider 实例
final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref)
{
    final taskDao = ref.watch(taskDaoProvider);
    final downloadService = ref.watch(downloadServiceProvider);
    return DownloadNotifier(ref, taskDao, downloadService);
});
