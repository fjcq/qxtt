import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/library_storage.dart';

/// 存储信息概览条
/// 显示在下载页"已下载"分页顶部，汇总：
/// - 本子数量
/// - 已下载章节总数
/// - 本地占用空间
class StorageSummaryBar extends StatelessWidget
{
    /// 本子数量
    final int albumCount;

    /// 已下载章节总数
    final int episodeCount;

    /// 总占用字节
    final int totalBytes;

    /// 总文件数
    final int fileCount;

    /// 加载中
    final bool isLoading;

    /// 点击触发整库清理/扫描等更多操作
    final VoidCallback? onMoreTap;

    const StorageSummaryBar({
        super.key,
        required this.albumCount,
        required this.episodeCount,
        required this.totalBytes,
        this.fileCount = 0,
        this.isLoading = false,
        this.onMoreTap,
    });

    @override
    Widget build(BuildContext context)
    {
        return Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1f1a2c), Color(0xFF241f30)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                ),
            ),
            child: Row(
                children: [
                    // 图标
                    Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                            Icons.storage_rounded,
                            color: AppColors.accent,
                            size: 24,
                        ),
                    ),
                    const SizedBox(width: 12),
                    // 统计文本
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Row(
                                    children: [
                                        _StatText(
                                            value: '$albumCount',
                                            label: '本子',
                                        ),
                                        const _Divider(),
                                        _StatText(
                                            value: '$episodeCount',
                                            label: '章节',
                                        ),
                                        const _Divider(),
                                        _StatText(
                                            value: LibraryStorage.formatSize(totalBytes),
                                            label: '占用',
                                        ),
                                    ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    fileCount > 0
                                        ? '本地文件 $fileCount 个 · 离线随时可读'
                                        : '本子文件均已下载到本地',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textDisabled,
                                    ),
                                ),
                            ],
                        ),
                    ),
                    if (onMoreTap != null)
                        IconButton(
                            tooltip: '打开下载目录',
                            onPressed: onMoreTap,
                            icon: const Icon(
                                Icons.folder_open,
                                color: AppColors.textSecondary,
                            ),
                        ),
                    if (isLoading)
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                ),
                            ),
                        ),
                ],
            ),
        );
    }
}

/// 单项统计
class _StatText extends StatelessWidget
{
    final String value;
    final String label;

    const _StatText({required this.value, required this.label});

    @override
    Widget build(BuildContext context)
    {
        return Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                        ),
                    ),
                    Text(
                        label,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                        ),
                    ),
                ],
            ),
        );
    }
}

/// 统计项之间的细分隔
class _Divider extends StatelessWidget
{
    const _Divider();

    @override
    Widget build(BuildContext context)
    {
        return Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.divider,
        );
    }
}
