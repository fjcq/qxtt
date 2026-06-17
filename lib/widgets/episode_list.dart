import 'package:flutter/material.dart';

import '../core/jm/jm_entity.dart';
import '../theme/app_colors.dart';

/// 章节列表组件
class EpisodeList extends StatelessWidget
{
    /// 章节列表
    final List<Episode> episodes;

    /// 下载章节回调
    final ValueChanged<Episode>? onDownload;

    /// 阅读章节回调
    final ValueChanged<Episode>? onRead;

    /// 已下载章节的 photoId 集合
    /// 出现在此集合中的章节将不显示下载按钮（已下载）
    final Set<String>? downloadedPhotoIds;

    const EpisodeList({
        super.key,
        required this.episodes,
        this.onDownload,
        this.onRead,
        this.downloadedPhotoIds,
    });

    @override
    Widget build(BuildContext context)
    {
        if (episodes.isEmpty)
        {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        '暂无章节',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                        ),
                    ),
                ),
            );
        }

        return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const Divider(
                color: AppColors.divider,
                height: 1,
            ),
            itemBuilder: (context, index)
            {
                final episode = episodes[index];
                final isDownloaded = downloadedPhotoIds?.contains(episode.photoId) ?? false;
                return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                    ),
                    leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.surfaceVariant,
                        child: Text(
                            episode.index,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                            ),
                        ),
                    ),
                    title: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                        ),
                    ),
                    trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            // 已下载标识
                            if (isDownloaded)
                                const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: AppColors.success,
                                    ),
                                ),
                            // 阅读按钮
                            if (onRead != null)
                                IconButton(
                                    icon: const Icon(
                                        Icons.menu_book_outlined,
                                        size: 20,
                                        color: AppColors.accent,
                                    ),
                                    onPressed: () => onRead!(episode),
                                    tooltip: '阅读',
                                ),
                            // 下载按钮：已下载则不显示，避免重复下载
                            if (onDownload != null && !isDownloaded)
                                IconButton(
                                    icon: const Icon(
                                        Icons.download_outlined,
                                        size: 20,
                                        color: AppColors.textSecondary,
                                    ),
                                    onPressed: () => onDownload!(episode),
                                    tooltip: '下载',
                                ),
                        ],
                    ),
                );
            },
        );
    }
}
