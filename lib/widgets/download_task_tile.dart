import 'dart:io';

import 'package:flutter/material.dart';

import '../providers/download_provider.dart';
import '../theme/app_colors.dart';
import 'download_progress.dart';

/// 单个下载任务展示卡片
/// 涵盖 active / completed / failed 三种状态
class DownloadTaskTile extends StatelessWidget
{
    final DownloadTaskView view;

    /// 点击回调（completed 任务进入阅读）
    final VoidCallback? onTap;

    /// 取消/重试/删除按钮的回调
    final VoidCallback? onCancel;

    /// 重试按钮回调
    final VoidCallback? onRetry;

    /// 删除按钮回调
    final VoidCallback? onDelete;

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
    static Color statusColorOf(String status)
    {
        switch (status)
        {
            case 'completed':
                return AppColors.success;
            case 'running':
                return AppColors.accent;
            case 'failed':
                return AppColors.error;
            case 'cancelled':
                return AppColors.textDisabled;
            default:
                return AppColors.textSecondary;
        }
    }

    const DownloadTaskTile({
        super.key,
        required this.view,
        this.onTap,
        this.onCancel,
        this.onRetry,
        this.onDelete,
        this.isEditing = false,
        this.isSelected = false,
    });

    @override
    Widget build(BuildContext context)
    {
        final task = view.task;
        final statusColor = statusColorOf(task.status);
        final statusText = statusTextOf(task.status);

        return InkWell(
            onTap: isEditing ? () => onTap?.call() : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
                children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.divider.withValues(alpha: 0.4),
                                width: isSelected ? 2 : 1,
                            ),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                // 缩略图 + 标题 + 状态
                                Row(
                                    children: [
                                        _buildThumbnail(),
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
                                                        style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                AppColors.textPrimary,
                                                        ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                        view.isAlbumTask
                                                            ? '整本下载'
                                                            : '单章下载',
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                AppColors.textDisabled,
                                                        ),
                                                    ),
                                                ],
                                            ),
                                        ),
                                        const SizedBox(width: 8),
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
                                    ],
                                ),
                                const SizedBox(height: 10),
                                // 进度
                                if (view.isActive)
                                    DownloadProgress(
                                        progress: task.progress,
                                        statusText: task.message,
                                        countText:
                                            '${task.currentImage}/${task.totalImages}',
                                        speedText: task.speed,
                                    )
                                else
                                    _buildFinishedSummary(),
                                const SizedBox(height: 8),
                                // 操作按钮
                                if (!isEditing) _buildActionRow(),
                            ],
                        ),
                    ),
                    if (isEditing) _buildSelectionBadge(),
                ],
            ),
        );
    }

    /// 缩略图：封面/首张图；不存在时回退到状态图标
    Widget _buildThumbnail()
    {
        final task = view.task;
        const size = 56.0;
        final radius = BorderRadius.circular(8);
        final coverPath = task.coverPath ?? '';
        Widget content;
        if (coverPath.isNotEmpty && File(coverPath).existsSync())
        {
            content = Image.file(
                File(coverPath),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _statusIconBox(size),
            );
        }
        else
        {
            content = _statusIconBox(size);
        }
        return ClipRRect(borderRadius: radius, child: content);
    }

    /// 状态图标方块（缩略图缺图时回退）
    Widget _statusIconBox(double size)
    {
        final task = view.task;
        IconData icon;
        Color color;
        if (task.status == 'completed')
        {
            icon = Icons.check_circle;
            color = AppColors.success;
        }
        else if (task.status == 'failed')
        {
            icon = Icons.error;
            color = AppColors.error;
        }
        else if (task.status == 'cancelled')
        {
            icon = Icons.do_disturb_alt;
            color = AppColors.textDisabled;
        }
        else if (task.status == 'running')
        {
            icon = Icons.cloud_download;
            color = AppColors.accent;
        }
        else
        {
            icon = Icons.hourglass_empty;
            color = AppColors.textSecondary;
        }
        return Container(
            width: size,
            height: size,
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 28),
        );
    }

    /// 已结束任务的汇总信息
    Widget _buildFinishedSummary()
    {
        final task = view.task;
        if (task.status == 'completed')
        {
            return Text(
                '共 ${task.totalImages} 张',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
                    ? AppColors.error
                    : AppColors.textDisabled,
            ),
        );
    }

    /// 操作按钮行
    Widget _buildActionRow()
    {
        final buttons = <Widget>[];
        if (view.isActive && onCancel != null)
        {
            buttons.add(TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('取消'),
            ));
        }
        if (view.isRetryable && onRetry != null)
        {
            buttons.add(TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                onPressed: onRetry,
            ));
        }
        if (!view.isActive && onDelete != null)
        {
            buttons.add(TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
    Widget _buildSelectionBadge()
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
                        ? AppColors.accent
                        : AppColors.surface.withValues(alpha: 0.7),
                    border: Border.all(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textDisabled,
                        width: 1.5,
                    ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.background,
                    )
                    : null,
            ),
        );
    }
}
