import 'dart:io';

import 'package:flutter/material.dart';

import '../providers/download_provider.dart';
import '../theme/app_colors.dart';
import '../utils/file_helper.dart';
import 'download_progress.dart';

/// 单个下载任务展示卡片
    /// 涵盖 active / paused / completed / failed / cancelled 五种状态
    class DownloadTaskTile extends StatelessWidget
    {
        final DownloadTaskView view;

        /// 点击回调（completed 任务进入阅读；非编辑模式下也用于「阅读」）
        final VoidCallback? onTap;

        /// 取消按钮回调（仅 active 任务）
        final VoidCallback? onCancel;

        /// 暂停按钮回调（仅 active 任务）
        final VoidCallback? onPause;

        /// 继续按钮回调（仅 paused 任务）
        final VoidCallback? onResume;

        /// 重试按钮回调
        final VoidCallback? onRetry;

        /// 删除按钮回调
        final VoidCallback? onDelete;

        /// 阅读按钮回调（下载中/已暂停/失败 任务，只要已有可读内容即可点击）
        final VoidCallback? onRead;

        /// 是否处于编辑模式
        final bool isEditing;

        /// 是否被选中（仅在 isEditing=true 时使用）
        final bool isSelected;

        /// 状态文本（自动根据 status 推导）
        static String statusTextOf(String status)
        {
            switch (status)
            {
                case 'pending':
                    return '等待中';
                case 'running':
                    return '下载中';
                case 'paused':
                    return '已暂停';
                case 'completed':
                    return '已完成';
                case 'failed':
                    return '下载失败';
                case 'cancelled':
                    return '已取消';
                default:
                    return status;
            }
        }

        /// 状态颜色
        static Color statusColorOf(BuildContext context, String status)
        {
            switch (status)
            {
                case 'completed':
                    return context.appColors.success;
                case 'running':
                    return context.appColors.accent;
                case 'paused':
                    return context.appColors.warning;
                case 'failed':
                    return context.appColors.error;
                case 'cancelled':
                    return context.appColors.textDisabled;
                default:
                    return context.appColors.textSecondary;
            }
        }

        const DownloadTaskTile({
            super.key,
            required this.view,
            this.onTap,
            this.onCancel,
            this.onPause,
            this.onResume,
            this.onRetry,
            this.onDelete,
            this.onRead,
            this.isEditing = false,
            this.isSelected = false,
        });

    @override
    Widget build(BuildContext context)
    {
        final task = view.task;
        final statusColor = statusColorOf(context, task.status);
        final statusText = statusTextOf(task.status);

        // 非编辑模式下，若已有可读内容，点击卡片整体即可进入阅读
        final tapCallback = isEditing
            ? (onTap == null ? null : () => onTap?.call())
            : (onRead ?? onTap);

        return InkWell(
            onTap: tapCallback,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
                children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: context.appColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isSelected
                                    ? context.appColors.accent
                                    : context.appColors.divider.withValues(alpha: 0.4),
                                width: isSelected ? 2 : 1,
                            ),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                // 缩略图 + 标题 + 状态
                                Row(
                                    children: [
                                        _buildThumbnail(context),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                    Text(
                                                        view.displayTitle,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                context.appColors.textPrimary,
                                                        ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                        view.isAlbumTask
                                                            ? '整本下载'
                                                            : '单章下载',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                context.appColors.textDisabled,
                                                        ),
                                                    ),
                                                ],
                                            ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                                Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(alpha: 0.15),
                                                        borderRadius:
                                                            BorderRadius.circular(10),
                                                    ),
                                                    child: Text(
                                                        statusText,
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: statusColor,
                                                            fontWeight: FontWeight.w500,
                                                        ),
                                                    ),
                                                ),
                                                if (view.hasReadableContent &&
                                                    !isEditing) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                        padding: const EdgeInsets
                                                                .symmetric(
                                                            horizontal: 6,
                                                            vertical: 1,
                                                        ),
                                                        decoration: BoxDecoration(
                                                            color: context.appColors
                                                                .accent
                                                                .withValues(alpha: 0.12),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                    8),
                                                        ),
                                                        child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize.min,
                                                            children: [
                                                                Icon(
                                                                    Icons
                                                                        .menu_book_outlined,
                                                                    size: 10,
                                                                    color: context
                                                                        .appColors
                                                                        .accent,
                                                                ),
                                                                const SizedBox(
                                                                    width: 2),
                                                                Text(
                                                                    '可读',
                                                                    style: TextStyle(
                                                                        fontSize: 10,
                                                                        color: context
                                                                            .appColors
                                                                            .accent,
                                                                    ),
                                                                ),
                                                            ],
                                                        ),
                                                    ),
                                                ],
                                            ],
                                        ),
                                    ],
                                ),
                                const SizedBox(height: 10),
                                // 进度（active 与 paused 都显示当前进度）
                                if (view.isActive || view.isPaused)
                                    DownloadProgress(
                                        progress: task.progress,
                                        statusText: view.isPaused
                                            ? '已暂停（点击继续）'
                                            : task.message,
                                        countText:
                                            '${task.currentImage}/${task.totalImages}',
                                        speedText: view.isPaused ? '' : task.speed,
                                    )
                                else
                                    _buildFinishedSummary(context),
                                const SizedBox(height: 8),
                                // 操作按钮
                                if (!isEditing) _buildActionRow(context),
                            ],
                        ),
                    ),
                    if (isEditing) _buildSelectionBadge(context),
                ],
            ),
        );
    }

    /// 缩略图：封面/首张图；不存在时回退到状态图标
    Widget _buildThumbnail(BuildContext context)
    {
        final task = view.task;
        const size = 56.0;
        final radius = BorderRadius.circular(8);
        final coverPath = task.coverPath ?? '';

        if (coverPath.isEmpty)
        {
            return ClipRRect(
                borderRadius: radius,
                child: _statusIconBox(context, size),
            );
        }

        return ClipRRect(
            borderRadius: radius,
            child: FutureBuilder<bool>(
                future: FileExistenceCache.fileExists(coverPath),
                builder: (context, snapshot)
                {
                    final hasCover = snapshot.data ?? false;
                    if (hasCover)
                    {
                        return Image.file(
                            File(coverPath),
                            width: size,
                            height: size,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _statusIconBox(context, size),
                        );
                    }
                    return _statusIconBox(context, size);
                },
            ),
        );
    }

    /// 状态图标方块（缩略图缺图时回退）
    Widget _statusIconBox(BuildContext context, double size)
    {
        final task = view.task;
        IconData icon;
        Color color;
        if (task.status == 'completed')
        {
            icon = Icons.check_circle;
            color = context.appColors.success;
        }
        else if (task.status == 'failed')
        {
            icon = Icons.error;
            color = context.appColors.error;
        }
        else if (task.status == 'paused')
        {
            icon = Icons.pause_circle_filled;
            color = context.appColors.warning;
        }
        else if (task.status == 'cancelled')
        {
            icon = Icons.do_disturb_alt;
            color = context.appColors.textDisabled;
        }
        else if (task.status == 'running')
        {
            icon = Icons.cloud_download;
            color = context.appColors.accent;
        }
        else
        {
            icon = Icons.hourglass_empty;
            color = context.appColors.textSecondary;
        }
        return Container(
            width: size,
            height: size,
            color: context.appColors.surfaceVariant,
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 28),
        );
    }

    /// 已结束任务的汇总信息
    Widget _buildFinishedSummary(BuildContext context)
    {
        final task = view.task;
        if (task.status == 'completed')
        {
            return Text(
                '共 ${task.totalImages} 张',
                style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.textSecondary,
                ),
            );
        }
        return Text(
            task.message.isNotEmpty ? task.message : '可点击重试按钮重新下载',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: task.status == 'failed'
                    ? context.appColors.error
                    : context.appColors.textDisabled,
            ),
        );
    }

    /// 操作按钮行
    Widget _buildActionRow(BuildContext context)
    {
        final buttons = <Widget>[];
        // 「阅读」按钮：只要有可读内容（非编辑模式）即可显示，置顶最左
        if (!isEditing && view.hasReadableContent && onRead != null)
        {
            buttons.add(TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('阅读'),
                style: TextButton.styleFrom(
                    foregroundColor: context.appColors.accent,
                ),
                onPressed: onRead,
            ));
        }
        if (view.isActive)
        {
            if (onPause != null)
            {
                buttons.add(TextButton.icon(
                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                    label: const Text('暂停'),
                    style: TextButton.styleFrom(
                        foregroundColor: context.appColors.warning,
                    ),
                    onPressed: onPause,
                ));
            }
            if (onCancel != null)
            {
                buttons.add(TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                        foregroundColor: context.appColors.textSecondary,
                    ),
                    child: const Text('取消'),
                ));
            }
        }
        if (view.isPaused)
        {
            if (onResume != null)
            {
                buttons.add(TextButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('继续'),
                    style: TextButton.styleFrom(
                        foregroundColor: context.appColors.accent,
                    ),
                    onPressed: onResume,
                ));
            }
            if (onCancel != null)
            {
                buttons.add(TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                        foregroundColor: context.appColors.textSecondary,
                    ),
                    child: const Text('取消'),
                ));
            }
        }
        if (view.isRetryable && onRetry != null)
        {
            buttons.add(TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
                style: TextButton.styleFrom(
                    foregroundColor: context.appColors.accent,
                ),
                onPressed: onRetry,
            ));
        }
        if (!view.isActive && !view.isPaused && onDelete != null)
        {
            buttons.add(TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                    foregroundColor: context.appColors.error,
                ),
                child: const Text('删除'),
            ));
        }
        if (buttons.isEmpty) return const SizedBox(height: 0);
        return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: buttons,
        );
    }

    /// 编辑模式选中标识
    Widget _buildSelectionBadge(BuildContext context)
    {
        return Positioned(
            top: 8,
            right: 8,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? context.appColors.accent
                        : context.appColors.surface.withValues(alpha: 0.7),
                    border: Border.all(
                        color: isSelected
                            ? context.appColors.accent
                            : context.appColors.textDisabled,
                        width: 1.5,
                    ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: context.appColors.background,
                    )
                    : null,
            ),
        );
    }
}
