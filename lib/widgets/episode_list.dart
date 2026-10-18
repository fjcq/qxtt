import 'package:flutter/material.dart';

import '../core/jm/jm_entity.dart';
import '../data/models/download_task_model.dart';
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

    /// 章节级下载进度映射（photoId → 进度）
    ///
    /// 由详情页合并 album 任务与 photo 任务的进度后传入；
    /// 命中的章节行显示独立进度条（替代下载按钮）
    final Map<String, ChapterProgress> chapterProgress;

    /// 是否存在关联的下载任务（album 任务"正在获取详情"阶段
    /// 尚无各章节进度数据，此时对未下载章节显示等待状态）
    final bool hasActiveTask;

    const EpisodeList({
        super.key,
        required this.episodes,
        this.onDownload,
        this.onRead,
        this.downloadedPhotoIds,
        this.chapterProgress = const {},
        this.hasActiveTask = false,
    });

    @override
    Widget build(BuildContext context)
    {
        if (episodes.isEmpty)
        {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        '暂无章节',
                        style: TextStyle(
                            color: context.appColors.textSecondary,
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
            separatorBuilder: (_, __) => Divider(
                color: context.appColors.divider,
                height: 1,
            ),
            itemBuilder: (context, index)
            {
                final episode = episodes[index];
                final isDownloaded = downloadedPhotoIds?.contains(episode.photoId) ?? false;
                final progress = chapterProgress[episode.photoId];
                return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                    ),
                    leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: context.appColors.surfaceVariant,
                        child: Text(
                            episode.index,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.textPrimary,
                            ),
                        ),
                    ),
                    title: Text(
                        episode.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            color: context.appColors.textPrimary,
                        ),
                    ),
                    trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            // 已下载标识
                            if (isDownloaded)
                                Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: context.appColors.success,
                                    ),
                                )
                            // 下载中的章节：显示独立进度条 + 已完成/总页数
                            else if (progress != null)
                                _ChapterProgressIndicator(progress: progress)
                            // 有关联任务但该章节尚无进度数据（正在获取详情）：
                            // 显示等待状态
                            else if (hasActiveTask)
                                const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                )
                            // 下载按钮：已下载/下载中则不显示，避免重复下载
                            else if (onDownload != null)
                                IconButton(
                                    icon: Icon(
                                        Icons.download_outlined,
                                        size: 20,
                                        color: context.appColors.textSecondary,
                                    ),
                                    onPressed: () => onDownload!(episode),
                                    tooltip: '下载',
                                ),
                            // 阅读按钮
                            if (onRead != null)
                                IconButton(
                                    icon: Icon(
                                        Icons.menu_book_outlined,
                                        size: 20,
                                        color: context.appColors.accent,
                                    ),
                                    onPressed: () => onRead!(episode),
                                    tooltip: '阅读',
                                ),
                        ],
                    ),
                );
            },
        );
    }
}

/// 章节行内嵌的下载进度指示器
///
/// 紧凑布局：细进度条（固定宽度）+ "已完成/总页数" 小字，
/// 用于在章节列表行内实时展示该章节的下载进度
class _ChapterProgressIndicator extends StatelessWidget
{
    /// 章节进度数据
    final ChapterProgress progress;

    const _ChapterProgressIndicator({required this.progress});

    @override
    Widget build(BuildContext context)
    {
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                    SizedBox(
                        width: 64,
                        child: LinearProgressIndicator(
                            value: progress.ratio,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            backgroundColor: context.appColors.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                context.appColors.accent,
                            ),
                        ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                        progress.total > 0
                            ? '${progress.completed}/${progress.total}'
                            : '${progress.completed} 张',
                        style: TextStyle(
                            fontSize: 10,
                            color: context.appColors.textSecondary,
                        ),
                    ),
                ],
            ),
        );
    }
}
