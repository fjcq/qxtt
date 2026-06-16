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

    const EpisodeList({
        super.key,
        required this.episodes,
        this.onDownload,
        this.onRead,
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
                            // 下载按钮
                            if (onDownload != null)
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
