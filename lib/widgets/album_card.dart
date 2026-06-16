import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/jm/jm_entity.dart';
import '../theme/app_colors.dart';

/// 本子卡片组件
class AlbumCard extends StatelessWidget
{
    /// 搜索结果项
    final SearchItem album;

    /// 点击回调
    final VoidCallback? onTap;

    const AlbumCard({
        super.key,
        required this.album,
        this.onTap,
    });

    @override
    Widget build(BuildContext context)
    {
        return GestureDetector(
            onTap: onTap,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                        ),
                    ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // 封面图
                        Expanded(
                            child: _buildCover(),
                        ),
                        // 标题和信息
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(
                                        album.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                        ),
                                    ),
                                    if (album.author.isNotEmpty)
                                        Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                                album.author,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textSecondary,
                                                ),
                                            ),
                                        ),
                                ],
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 构建封面图
    Widget _buildCover()
    {
        if (album.coverUrl.isNotEmpty)
        {
            return CachedNetworkImage(
                imageUrl: album.coverUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => _buildPlaceholder(),
                errorWidget: (context, url, error) => _buildPlaceholder(),
                httpHeaders: const {
                    'Referer': 'https://www.cdnhjk.net/',
                },
            );
        }
        return _buildPlaceholder();
    }

    /// 构建占位图
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
}
