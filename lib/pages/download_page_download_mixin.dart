import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/download_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/download_task_tile.dart';
import 'download_page.dart';

/// 下载中分页状态与 UI 封装
mixin DownloadPageDownloadMixin on ConsumerState<DownloadPage>
{
    /// 是否处于任务编辑模式
    bool get isTaskEditMode;

    /// 设置任务编辑模式
    set isTaskEditMode(bool value);

    /// 当前选中的 taskId
    Set<String> get selectedTaskIds;

    /// 显示 SnackBar 回调
    void showSnack(String text);

    /// 通用确认弹窗回调
    Future<bool> confirm({
        required String title,
        required String message,
        String confirmText,
        bool danger,
    });

    /// 构建下载中分页主体
    Widget buildDownloadTab()
    {
        final state = ref.watch(downloadProvider);
        if (state.tasks.isEmpty)
        {
            return _buildEmptyDownload();
        }
        return RefreshIndicator(
            color: context.appColors.accent,
            backgroundColor: context.appColors.surface,
            onRefresh: () async
            {
                await ref.read(downloadProvider.notifier).refresh();
            },
            child: _buildDownloadList(state),
        );
    }

    /// 下载中分页列表
    Widget _buildDownloadList(DownloadState state)
    {
        final grouped = state.grouped;
        final active = grouped[DownloadTaskGroup.active]!;
        final paused = grouped[DownloadTaskGroup.paused]!;
        final failed = grouped[DownloadTaskGroup.failed]!;

        return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
                if (active.isNotEmpty) ...[
                    _buildSectionHeader(
                        icon: Icons.cloud_download,
                        title: '正在下载',
                        count: active.length,
                        color: context.appColors.accent,
                    ),
                    const SizedBox(height: 8),
                    ...active.map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DownloadTaskTile(
                                view: v,
                                onRead: v.hasReadableContent
                                    ? () => _openTaskReader(v)
                                    : null,
                                onPause: () =>
                                    ref.read(downloadProvider.notifier)
                                        .pauseTask(v.task.taskId),
                                onCancel: () =>
                                    ref.read(downloadProvider.notifier)
                                        .cancelTask(v.task.taskId),
                            ),
                        )),
                ],
                if (paused.isNotEmpty) ...[
                    if (active.isNotEmpty) const SizedBox(height: 4),
                    _buildSectionHeader(
                        icon: Icons.pause_circle_filled,
                        title: '已暂停',
                        count: paused.length,
                        color: context.appColors.warning,
                    ),
                    const SizedBox(height: 8),
                    ...paused.map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DownloadTaskTile(
                                view: v,
                                onRead: v.hasReadableContent
                                    ? () => _openTaskReader(v)
                                    : null,
                                onResume: () =>
                                    ref.read(downloadProvider.notifier)
                                        .resumeTask(v.task.taskId),
                                onCancel: () =>
                                    ref.read(downloadProvider.notifier)
                                        .cancelTask(v.task.taskId),
                                onDelete: () =>
                                    _confirmDeleteTask(v.task.taskId),
                            ),
                        )),
                ],
                if (failed.isNotEmpty) ...[
                    if (active.isNotEmpty || paused.isNotEmpty)
                        const SizedBox(height: 4),
                    _buildSectionHeader(
                        icon: Icons.error_outline,
                        title: '失败 / 已取消',
                        count: failed.length,
                        color: context.appColors.error,
                    ),
                    const SizedBox(height: 8),
                    ...failed.map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DownloadTaskTile(
                                view: v,
                                isEditing: isTaskEditMode,
                                isSelected:
                                    selectedTaskIds.contains(v.task.taskId),
                                onTap: () => isTaskEditMode
                                    ? _toggleSelectTask(v.task.taskId)
                                    : null,
                                onRead: v.hasReadableContent
                                    ? () => _openTaskReader(v)
                                    : null,
                                onRetry: () =>
                                    ref.read(downloadProvider.notifier)
                                        .retryTask(v.task.taskId),
                                onDelete: () =>
                                    _confirmDeleteTask(v.task.taskId),
                            ),
                        )),
                ],
            ],
        );
    }

    /// 分组标题
    Widget _buildSectionHeader({
        required IconData icon,
        required String title,
        required int count,
        required Color color,
    })
    {
        return Row(
            children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                    title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.appColors.textPrimary,
                    ),
                ),
                const SizedBox(width: 6),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '$count',
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w500,
                        ),
                    ),
                ),
            ],
        );
    }

    /// 空状态
    Widget _buildEmptyDownload()
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.cloud_off,
                            size: 64,
                            color: context.appColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '暂无下载任务',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '到本子详情页发起下载',
                            style: TextStyle(
                                color: context.appColors.textDisabled,
                                fontSize: 12,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 切换单个任务选中
    void _toggleSelectTask(String taskId)
    {
        setState(()
        {
            if (selectedTaskIds.contains(taskId))
            {
                selectedTaskIds.remove(taskId);
            }
            else
            {
                selectedTaskIds.add(taskId);
            }
        });
    }

    /// 打开下载中任务的阅读器
    ///
    /// 根据 [view] 的任务类型决定路由：
    /// - 整本任务：跳转到第一个已下载章节（部分下载也可阅读，缺失页走网络）
    /// - 单章任务：跳转到任务对应的 chapter
    /// 通过 reader 的混合渲染（本地优先 + 缺失走网络）实现「边下边看」
    void _openTaskReader(DownloadTaskView view)
    {
        final photoId = view.readablePhotoId;
        if (photoId == null || photoId.isEmpty)
        {
            showSnack('该任务暂无可读内容');
            return;
        }
        final isAlbum = view.isAlbumTask;
        showSnack(isAlbum
            ? '进入阅读（已下载部分即时显示，未下载页将在线加载）'
            : '进入阅读（已下载部分即时显示，未下载页将在线加载）');
        context.push('/reader/$photoId');
    }

    /// 全选/取消全选任务
    void toggleSelectAllTasks()
    {
        final all = ref.read(downloadProvider).tasks;
        setState(()
        {
            if (selectedTaskIds.length == all.length)
            {
                selectedTaskIds.clear();
            }
            else
            {
                selectedTaskIds
                  ..clear()
                  ..addAll(all.map((t) => t.taskId));
            }
        });
    }

    /// 反选任务
    void invertTaskSelection()
    {
        final all = ref.read(downloadProvider).tasks;
        setState(()
        {
            final inverted = all
                .map((t) => t.taskId)
                .where((id) => !selectedTaskIds.contains(id))
                .toSet();
            selectedTaskIds
              ..clear()
              ..addAll(inverted);
        });
    }

    /// 确认重试选中的任务
    Future<void> confirmRetrySelectedTasks() async
    {
        if (selectedTaskIds.isEmpty)
        {
            showSnack('请先选择要重试的项');
            return;
        }
        final n = await ref
            .read(downloadProvider.notifier)
            .retryTasks(selectedTaskIds);
        if (!mounted) return;
        setState(() => selectedTaskIds.clear());
        showSnack('已重试 $n 个任务');
    }

    /// 确认删除选中的任务
    Future<void> confirmDeleteSelectedTasks() async
    {
        if (selectedTaskIds.isEmpty)
        {
            showSnack('请先选择要删除的项');
            return;
        }
        final ok = await confirm(
            title: '删除 ${selectedTaskIds.length} 个任务',
            message: '将删除这些下载任务的记录，同时清理可能存在的本地部分文件。',
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        final (total, failed) = await ref
            .read(downloadProvider.notifier)
            .deleteTasks(selectedTaskIds);
        if (!mounted) return;
        setState(() => selectedTaskIds.clear());
        showSnack(failed == 0
            ? '已删除 $total 个任务'
            : '已删除 $total 个，$failed 个失败');
    }

    /// 单个任务删除
    Future<void> _confirmDeleteTask(String taskId) async
    {
        final task = ref
            .read(downloadProvider)
            .tasks
            .where((t) => t.taskId == taskId)
            .firstOrNull;
        if (task == null) return;
        final isAlbum = task.taskType == 'album';
        final message = isAlbum
            ? '将删除该任务并清理整本漫画的本地文件（已下载部分）。'
            : '将删除该任务并清理该章节的本地文件。';
        final ok = await confirm(
            title: '删除任务',
            message: message,
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        await ref.read(downloadProvider.notifier).deleteTask(taskId);
    }

    /// 下载中分页菜单回调
    void handleDownloadMenu(String value) async
    {
        switch (value)
        {
            case 'open_dir':
                break;
            case 'retry_all':
                final n = await ref.read(downloadProvider.notifier).retryAllFailed();
                if (mounted) showSnack('已重试 $n 个任务');
                break;
            case 'resume_all':
                final n = await ref.read(downloadProvider.notifier).resumeAllPaused();
                if (mounted) showSnack('已继续 $n 个任务');
                break;
            case 'pause_all':
                final ok = await confirm(
                    title: '全部暂停',
                    message: '将暂停所有正在下载的任务，已下载的部分文件保留。',
                    confirmText: '全部暂停',
                );
                if (ok)
                {
                    await ref.read(downloadProvider.notifier).pauseAllActive();
                    if (mounted) showSnack('已暂停所有活动任务');
                }
                break;
            case 'cancel_all':
                final ok = await confirm(
                    title: '全部取消',
                    message: '将取消所有正在下载或等待中的任务。\n未完成的本地部分文件保留。',
                    confirmText: '全部取消',
                    danger: true,
                );
                if (ok)
                {
                    await ref.read(downloadProvider.notifier).cancelAllActive();
                }
                break;
            case 'clear_failed':
                final ok = await confirm(
                    title: '清除失败 / 已取消记录',
                    message: '将删除所有失败与已取消的任务记录，同时清理对应的本地部分文件。',
                    confirmText: '清除',
                    danger: true,
                );
                if (ok)
                {
                    final n = await ref.read(downloadProvider.notifier).clearFailed();
                    if (mounted) showSnack('已清除 $n 条记录');
                }
                break;
        }
    }
}
