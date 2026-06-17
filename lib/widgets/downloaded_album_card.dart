import 'dart:io';

import 'package:flutter/material.dart';

import '../data/models/library_album_model.dart';
import '../theme/app_colors.dart';
import '../utils/library_storage.dart';

/// 已下载漫画卡片
/// 相比原 AlbumCard：
/// - 显示作者、已下载章节数、本地占用
/// - 在编辑模式下显示多选标识
/// - 阅读进度可视化
class DownloadedAlbumCard extends StatelessWidget
{
    final LibraryAlbumModel album;

    /// 点击回调（普通模式：进入阅读；编辑模式：切换选中）
    final VoidCallback? onTap;

    /// 长按回调
    final VoidCallback? onLongPress;

    /// 是否处于编辑模式
    final bool isEditing;

    /// 是否被选中
    final bool isSelected;

    const DownloadedAlbumCard({
        super.key,
        required this.album,
        this.onTap,
        this.onLongPress,
        this.isEditing = false,
        this.isSelected = false,
    });

    @override
    Widget build(BuildContext context)
    {
        final hasRead = album.lastReadPage > 0;
        return GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
                children: [
                    _buildCard(context, hasRead: hasRead),
                    if (isEditing) _buildSelectionBadge(),
                ],
            ),
        );
    }

    /// 主卡片
    Widget _buildCard(BuildContext context, {required bool hasRead})
    {
        return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: AppColors.accent, width: 2)
                    : Border.all(
                        color: AppColors.divider.withValues(alpha: 0.4),
                    ),
                boxShadow: const [
                    BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                    ),
                ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // 封面
                    Expanded(child: _buildCover()),
                    // 标题 + 信息
                    Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text(
                                    album.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                        height: 1.25,
                                    ),
                                ),
                                const SizedBox(height: 4),
                                _buildInfoRow(),
                            ],
                        ),
                    ),
                ],
            ),
        );
    }

    /// 封面图
    Widget _buildCover()
    {
        if (album.coverPath.isNotEmpty && File(album.coverPath).existsSync())
        {
            return Image.file(
                File(album.coverPath),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
            );
        }
        return _buildPlaceholder();
    }

    /// 封面占位
    Widget _buildPlaceholder()
    {
        return Container(
            color: AppColors.surfaceVariant,
            child: const Center(
                child: Icon(
                    Icons.image_outlined,
                    color: AppColors.textDisabled,
                    size: 32,
                ),
            ),
        );
    }

    /// 信息行：作者、已下载章节数、占用空间、最后阅读
    Widget _buildInfoRow()
    {
        final infoParts = <String>[];
        if (album.author.isNotEmpty) infoParts.add(album.author);
        if (album.downloadedEpisodes.isNotEmpty)
        {
            infoParts.add('${album.downloadedEpisodes.length}话');
        }
        if (album.sizeBytes > 0)
        {
            infoParts.add(LibraryStorage.formatSize(album.sizeBytes));
        }
        if (album.lastReadPage > 0)
        {
            infoParts.add('读至第${album.lastReadPage}页');
        }
        final text = infoParts.isEmpty ? '已下载' : infoParts.join(' · ');
        return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
            ),
        );
    }

    /// 编辑模式选中标识
    Widget _buildSelectionBadge()
    {
        return Positioned(
            top: 6,
            right: 6,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
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
                        size: 16,
                        color: AppColors.background,
                    )
                    : null,
            ),
        );
    }
}
