import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_service.dart';
import '../data/models/download_task_model.dart';
import 'config_provider.dart';
import 'download_notifier_base.dart';
import 'download_state.dart';
import 'download_task_scheduler.dart';
import 'library_provider.dart';
import 'search_provider.dart';

export 'download_notifier_base.dart';
export 'download_state.dart';
export 'download_task_scheduler.dart';
export 'download_task_view.dart';

/// 下载管理 Provider
/// 关键设计：
/// - 任务完成后 2 秒自动从列表与数据库中移除（不再出现在"下载中"Tab）
/// - 完成后 Library 接管已下载章节的所有权
/// - 删除 / 重试 / 取消操作默认清理本地文件
/// - 暂停 / 继续：保留已下载部分文件，按图片级断点续传
/// - 启动时自动恢复所有 `pending` 与 `paused` 任务
class DownloadNotifier extends DownloadNotifierBase
    with DownloadTaskSchedulerMixin
{
    /// 构造下载管理 Provider
    DownloadNotifier(super.ref, super.taskDao, super.downloadService)
    {
        _init();
    }

    /// 初始化：加载任务、监听进度、补全历史完成的任务到 library、
    /// 恢复未完成的任务
    void _init()
    {
        loadTasks().then((_) async
        {
            await _syncCompletedTasksToLibrary();
            await _recoverOnStartup();
        });
        progressSub = downloadService.onProgress.listen((progress)
        {
            _updateTaskProgress(progress);
        });
    }

    /// 应用启动时恢复未完成的任务
    /// - `pending` 任务：直接重新派发
    /// - `paused` 任务：重新派发（下载流程会自动跳过已有图片）
    /// - `running` 任务：通常由上次崩溃/直接关闭应用造成；保留已记录的进度
    ///   并标记为 `paused`，让用户主动继续（续传不会从头开始）
    Future<void> _recoverOnStartup() async
    {
        final toResume = <DownloadTaskModel>[];
        final toMarkPaused = <DownloadTaskModel>[];

        for (final t in state.tasks)
        {
            if (t.status == 'pending' || t.status == 'paused')
            {
                toResume.add(t);
            }
            else if (t.status == 'running')
            {
                // 上次崩溃遗留的"运行中"任务，标记为 paused 等用户主动继续
                toMarkPaused.add(t);
            }
        }

        for (final t in toMarkPaused)
        {
            // progress 传已持久化值：避免重启后进度条归零
            await taskDao.updateTaskStatus(
                t.taskId, 'paused', '上次未正常结束', t.progress,
            );
        }

        if (toMarkPaused.isNotEmpty)
        {
            await loadTasks();
        }

        for (final t in toResume)
        {
            // 续传：直接派发，下载流程会跳过本地已存在的图片
            if (t.taskType == 'album')
            {
                downloadService
                    .downloadAlbum(t.taskId, t.jmId)
                    .then((_) => loadTasks());
            }
            else
            {
                downloadService
                    .downloadPhoto(t)
                    .then((_) => loadTasks());
            }
        }
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
            loadTasks();
            return;
        }

        // 同步下载进度相关字段
        if (progress.downloadedPhotoIds.isNotEmpty)
        {
            targetTask.downloadedPhotoIds = progress.downloadedPhotoIds;
            // 增量同步到 library：让"边下边看"的入口即时可用
            _handlePartialDownloaded(targetTask);
        }
        // 同步边下边看集合：用于在章节未完全下载完时也能立即显示「阅读」入口
        if (progress.partialDownloadedPhotoIds.isNotEmpty)
        {
            targetTask.partialDownloadedPhotoIds = progress.partialDownloadedPhotoIds;
        }
        // 同步章节级进度映射：详情页据此渲染每章节的独立进度条；
        // 暂停/失败/取消事件也携带最后进度，保留供 UI 展示
        if (progress.chapterProgress.isNotEmpty)
        {
            targetTask.chapterProgress = progress.chapterProgress;
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

        // 单章任务的 localPath 是章节目录，书架需要记录本子根目录
        final String albumLocalPath;
        if (task.taskType == 'photo' && task.localPath.isNotEmpty)
        {
            final dir = Directory(task.localPath);
            albumLocalPath = dir.parent.path;
        }
        else
        {
            albumLocalPath = task.localPath;
        }

        ref.read(libraryProvider.notifier).markEpisodesDownloaded(
            task.albumId,
            task.downloadedPhotoIds,
            title: task.title,
            author: task.coverAuthor.isNotEmpty ? task.coverAuthor : null,
            coverPath: task.coverPath,
            localPath: albumLocalPath,
            pageCount: task.coverPageCount > 0 ? task.coverPageCount : null,
            episodeCount: task.coverEpisodeCount > 0 ? task.coverEpisodeCount : null,
        );
    }

    /// 增量入书架：每次进度事件携带已完成的章节列表时，调用此方法
    /// 立即把已完成的章节写入 library，让用户可以边下边看
    void _handlePartialDownloaded(DownloadTaskModel task)
    {
        if (task.albumId.isEmpty) return;
        if (task.downloadedPhotoIds.isEmpty) return;
        if (task.status != 'running') return;

        ref.read(libraryProvider.notifier).markEpisodesDownloaded(
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
        if (scheduledArchives.contains(taskId)) return;
        scheduledArchives.add(taskId);
        Future.delayed(const Duration(seconds: 2), () async
        {
            scheduledArchives.remove(taskId);
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
            await taskDao.deleteTask(taskId);
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

            final existing = await getDownloadedEpisodes(task.albumId);
            if (existing.isNotEmpty) continue;

            historicalCompleted.add(task);
            _handleDownloadCompleted(task);
        }
    }

    /// 加载所有任务
    @override
    Future<void> loadTasks() async
    {
        final tasks = await taskDao.getAllTasks();
        state = state.copyWith(tasks: tasks);
    }

    @override
    void dispose()
    {
        scheduledArchives.clear();
        historicalCompleted.clear();
        progressSub?.cancel();
        downloadService.dispose();
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
    final service = DownloadService(
        client: client,
        taskDao: taskDao,
        downloadDir: downloadDir,
        imageThreadCount: config.imageThreadCount,
        photoThreadCount: config.photoThreadCount,
    );
    // 监听 config 变更，实时更新并发数（已运行的下载批次信号量不变，
    // 仅影响之后新派发的图片）
    ref.listen<ConfigState>(configProvider, (prev, next)
    {
        service.imageThreadCount = next.config.imageThreadCount;
    });
    return service;
});

/// 下载管理 Provider 实例
final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref)
{
    final taskDao = ref.watch(taskDaoProvider);
    final downloadService = ref.watch(downloadServiceProvider);
    return DownloadNotifier(ref, taskDao, downloadService);
});

/// 指定本子关联的下载任务列表（family 按 albumId 缓存）
///
/// 匹配规则：
/// - album 类型任务：jmId == albumId（整本下载）
/// - photo 类型任务：albumId == albumId（该本子的单章下载）
/// 详情页据此渲染整本进度、章节级进度与暂停/继续/取消等操作
final albumDownloadTasksProvider =
    Provider.family<List<DownloadTaskModel>, String>((ref, albumId)
{
    final tasks = ref.watch(downloadProvider).tasks;
    return tasks
        .where((t) =>
            (t.taskType == 'album' && t.jmId == albumId) ||
            (t.taskType == 'photo' && t.albumId == albumId))
        .toList();
});
