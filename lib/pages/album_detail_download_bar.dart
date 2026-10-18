import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/download_task_model.dart';
import '../providers/download_provider.dart';
import '../theme/app_colors.dart';

/// 详情页底部下载状态栏
///
/// 展示整本（album）下载任务的实时进度与整本级操作：
/// - running：进度条 + "下载中 45% · 128/280 张 · 1.2MB/s" + 暂停按钮
/// - paused：进度条（灰）+ "已暂停" + 继续/取消按钮
/// - failed/cancelled：错误提示 + 重试/删除按钮
/// 单章（photo）任务的进度由章节列表行内进度条呈现，不在本栏重复展示
class AlbumDetailDownloadBar extends ConsumerWidget
{
    /// 整本下载任务
    final DownloadTaskModel task;

    const AlbumDetailDownloadBar({super.key, required this.task});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(
                color: context.appColors.surface,
                border: Border(
                    top: BorderSide(color: context.appColors.divider),
                ),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(
                        children: [
                            Expanded(
                                child: Text(
                                    _statusText(),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _statusColor(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                ),
                            ),
                            ..._buildActions(context, ref),
                        ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                        value: _barValue(),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                        backgroundColor: context.appColors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _statusColor(context),
                        ),
                    ),
                ],
            ),
        );
    }

    /// 进度条的填充比例（失败/取消时无意义，返回 null 显示不确定动画）
    double? _barValue()
    {
        if (task.status == 'running' || task.status == 'paused')
        {
            return task.totalImages > 0
                ? (task.progress).clamp(0.0, 1.0)
                : null;
        }
        return null;
    }

    /// 状态文字（含进度、速度与错误信息）
    String _statusText()
    {
        switch (task.status)
        {
            case 'running':
            case 'pending':
                final ratio = (task.progress * 100).toStringAsFixed(0);
                final count = task.totalImages > 0
                    ? ' · ${task.currentImage}/${task.totalImages} 张'
                    : '';
                final speed = task.speed.isNotEmpty ? ' · ${task.speed}' : '';
                return '下载中 $ratio%$count$speed';
            case 'paused':
                return '已暂停 · ${(task.progress * 100).toStringAsFixed(0)}%';
            case 'failed':
            case 'cancelled':
                return task.message.isNotEmpty ? task.message : '下载失败';
            case 'completed':
                return '下载完成';
            default:
                return task.message;
        }
    }

    /// 状态颜色：运行中强调色、暂停橙色、失败红色
    Color _statusColor(BuildContext context)
    {
        switch (task.status)
        {
            case 'running':
            case 'pending':
                return context.appColors.accent;
            case 'paused':
                return context.appColors.warning;
            case 'failed':
            case 'cancelled':
                return context.appColors.error;
            default:
                return context.appColors.textSecondary;
        }
    }

    /// 整本级操作按钮（暂停/继续/取消/重试/删除）
    List<Widget> _buildActions(BuildContext context, WidgetRef ref)
    {
        final notifier = ref.read(downloadProvider.notifier);
        switch (task.status)
        {
            case 'running':
            case 'pending':
                return [
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.pause_circle_outline, size: 22),
                        color: context.appColors.textSecondary,
                        tooltip: '暂停',
                        onPressed: () => notifier.pauseTask(task.taskId),
                    ),
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.cancel_outlined, size: 22),
                        color: context.appColors.textSecondary,
                        tooltip: '取消（保留已下载）',
                        onPressed: () => notifier.cancelTask(task.taskId),
                    ),
                ];
            case 'paused':
                return [
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.play_circle_outline, size: 22),
                        color: context.appColors.accent,
                        tooltip: '继续',
                        onPressed: () => notifier.resumeTask(task.taskId),
                    ),
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.cancel_outlined, size: 22),
                        color: context.appColors.textSecondary,
                        tooltip: '取消（保留已下载）',
                        onPressed: () => notifier.cancelTask(task.taskId),
                    ),
                ];
            case 'failed':
            case 'cancelled':
                return [
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 22),
                        color: context.appColors.accent,
                        tooltip: '重试',
                        onPressed: () => notifier.retryTask(task.taskId),
                    ),
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 22),
                        color: context.appColors.textSecondary,
                        tooltip: '删除任务',
                        onPressed: () => notifier.deleteTask(task.taskId),
                    ),
                ];
            default:
                return const [];
        }
    }
}
