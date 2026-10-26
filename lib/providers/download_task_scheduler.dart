import 'dart:io';

import '../core/download/download_service.dart';
import '../data/models/download_task_model.dart';
import '../utils/library_storage.dart';
import 'config_provider.dart';
import 'download_notifier_base.dart';
import 'download_task_view.dart';
import 'library_provider.dart';

/// 下载任务的调度层：创建、取消、暂停、继续、重试、删除、批量操作等
mixin DownloadTaskSchedulerMixin on DownloadNotifierBase
{
    /// 创建下载任务并开始下载
    /// 若存在未完成的同目标任务（pending/running/paused），不会重复创建；
    /// 其中 paused 任务会立即重新派发，按图片级断点续传继续下载
    /// 返回 (taskId, isNewlyCreated)
    Future<({String taskId, bool isNewlyCreated})> createAndStartDownload(
        String type,
        String jmId, {
        String? title,
        String? albumId,
        String? albumTitle,
        String? episodeIndex,
        String? episodeName,
    }) async
    {
        final effectiveAlbumId = albumId ?? (type == 'album' ? jmId : '');
        final existing = _findActiveDuplicate(type, jmId, effectiveAlbumId);
        if (existing != null)
        {
            // 暂停中的任务：用户再次点击下载即视为"继续"，直接续传
            if (existing.status == 'paused')
            {
                _dispatchTask(existing);
            }
            return (taskId: existing.taskId, isNewlyCreated: false);
        }

        final task = await downloadService.createTask(
            type,
            jmId,
            title: title,
            albumId: albumId,
            albumTitle: albumTitle,
            episodeIndex: episodeIndex,
            episodeName: episodeName,
        );
        await loadTasks();

        _dispatchTask(task);
        return (taskId: task.taskId, isNewlyCreated: true);
    }

    /// 派发一个已存在的任务（用于启动恢复与续传）
    void _dispatchTask(DownloadTaskModel task)
    {
        // 必须先清除暂停标记，否则下载流程内的 onPauseSignal 会立即把新下载取消
        downloadService.clearPausedFlag(task.taskId);
        if (task.taskType == 'album')
        {
            downloadService
                .downloadAlbum(task.taskId, task.jmId)
                .then((_) => loadTasks());
        }
        else
        {
            downloadService
                .downloadPhoto(task)
                .then((_) => loadTasks());
        }
    }

    /// 查找未完成（pending/running/paused）的同目标下载任务
    DownloadTaskModel? _findActiveDuplicate(
        String type,
        String jmId,
        String albumId,
    )
    {
        const activeStatuses = {'pending', 'running', 'paused'};
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
        downloadService.cancelTask(taskId);
        // progress 传 null：保留上次进度，避免取消后恢复时从 0 开始
        await taskDao.updateTaskStatus(taskId, 'cancelled', '已取消', null);
        await loadTasks();
    }

    /// 暂停下载任务
    /// - 取消正在进行的 HTTP 请求
    /// - 保留本地已下载的部分文件
    /// - 状态置为 `paused`，可通过 [resumeTask] 继续
    Future<void> pauseTask(String taskId) async
    {
        downloadService.pauseTask(taskId);
        // 状态由 downloadAlbum / downloadPhoto 在 finally 写回，
        // 这里也立即写一份，避免 UI 长时间停留在 running；进度保持不变
        await taskDao.updateTaskStatus(taskId, 'paused', '已暂停', null);
        await loadTasks();
    }

    /// 继续已暂停的下载任务
    /// - 不删除本地已下载的部分文件
    /// - 重新派发任务，下载流程会自动跳过已有图片
    /// - 已完成的任务不允许继续（按重试处理）
    Future<bool> resumeTask(String taskId) async
    {
        final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task == null) return false;
        if (task.status == 'paused')
        {
            // 续传：不清空文件，直接重派
            _dispatchTask(task);
            return true;
        }
        // 非 paused 状态走重试
        return retryTask(taskId);
    }

    /// 重试已失败/已取消的下载任务
    ///
    /// 【断点续传】保留本地已下载文件，重新派发任务后由下载流程扫描本地
    /// 已有图片并跳过，只补下缺失部分（含已下载完成本子的新增章节）。
    /// 仅在用户主动"删除任务"时才清理本地文件（见 [deleteTask]）。
    Future<bool> retryTask(String taskId) async
    {
        final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task == null) return false;
        if (!DownloadTaskView(task).isRetryable) return false;
        // paused 任务优先走续传，避免误清已下载的文件
        if (task.status == 'paused') return resumeTask(taskId);

        downloadService.cancelTask(taskId);
        // progress 传 null：保留断点进度，由重新派发的下载流程续算
        await taskDao.updateTaskStatus(taskId, 'pending', '准备重试', null);
        await loadTasks();
        _dispatchTask(task);
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

    /// 批量继续已暂停的任务
    Future<int> resumeTasks(Iterable<String> taskIds) async
    {
        var count = 0;
        for (final id in taskIds)
        {
            if (await resumeTask(id)) count++;
        }
        return count;
    }

    /// 删除下载任务
    /// [deleteFiles] 是否同时删除本地文件（默认 true）
    /// - active 任务：会先取消下载，再删除文件
    /// - failed/cancelled/paused 任务：直接删除记录与文件
    /// - completed 任务：通常已被自动归档，不应到达此处
    Future<void> deleteTask(
        String taskId, {
        bool deleteFiles = true,
    }) async
    {
        final task = state.tasks.where((t) => t.taskId == taskId).firstOrNull;
        downloadService.cancelTask(taskId);
        final remain = state.tasks.where((t) => t.taskId != taskId).toList();
        state = state.copyWith(tasks: remain);
        scheduledArchives.remove(taskId);
        if (deleteFiles && task != null)
        {
            await _cleanupTaskFiles(task);
        }
        try
        {
            await taskDao.deleteTask(taskId);
        }
        catch (_)
        {
            await loadTasks();
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
                await taskDao.deleteTask(id);
            }
            catch (_)
            {
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

    /// 全部继续已暂停任务
    Future<int> resumeAllPaused() async
    {
        final pausedIds = state.tasks
            .where((t) => t.status == 'paused')
            .map((t) => t.taskId)
            .toList();
        return resumeTasks(pausedIds);
    }

    /// 全部暂停活动任务
    Future<void> pauseAllActive() async
    {
        final activeIds = state.tasks
            .where((t) => t.status == 'running' || t.status == 'pending')
            .map((t) => t.taskId)
            .toList();
        for (final id in activeIds)
        {
            await pauseTask(id);
        }
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
        await loadTasks();
    }

    /// 获取指定本子已下载章节 ID 集合
    Future<Set<String>> getDownloadedEpisodes(String albumId) async
    {
        return ref.read(libraryProvider.notifier).getDownloadedEpisodes(albumId);
    }

    /// 解析下载目录
    /// 1) 等待 ConfigNotifier 完成初始化（避免首帧拿到空 downloadDir）
    /// 2) 优先使用配置值，为空时回退到默认目录
    Future<String> _resolveDownloadDir() async
    {
        await ref.read(configProvider.notifier).initialized;
        final configured = ref.read(configProvider).config.downloadDir;
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
        }
    }

    /// 文件名清洗（与 PathHelper.sanitizeFileName 规则保持一致）
    String _sanitize(String name)
    {
        var result = name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
        result = result.trimRight();
        while (result.endsWith('.'))
        {
            result = result.substring(0, result.length - 1);
        }
        if (result.isEmpty) result = 'unnamed';
        return result;
    }
}
