import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/jm/jm_image.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';

/// 详情页信息区组件：封面 + 标题 + 作者/页数/章节/日期/浏览等信息行
class AlbumDetailInfoSection extends ConsumerWidget
{
    /// 详情页状态（含 detail 与页数计算状态）
    final AlbumDetailState state;

    const AlbumDetailInfoSection({super.key, required this.state});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final detail = state.detail!;
        final client = ref.watch(jmClientProvider);
        final coverUrl = client.getAlbumCoverUrl(detail.albumId);

        return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // 封面
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                        imageUrl: coverUrl,
                        cacheManager: JmImageCacheManager.instance,
                        width: 120,
                        height: 160,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            width: 120,
                            height: 160,
                            color: context.appColors.surfaceVariant,
                            child: Center(
                                child: Icon(Icons.image, color: context.appColors.textDisabled),
                            ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                            width: 120,
                            height: 160,
                            color: context.appColors.surfaceVariant,
                            child: Center(
                                child: Icon(Icons.broken_image, color: context.appColors.textDisabled),
                            ),
                        ),
                    ),
                ),
                const SizedBox(width: 16),
                // 信息
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                                detail.name,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: context.appColors.textPrimary,
                                ),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(context, '作者', detail.author),
                            _buildInfoRow(
                                context,
                                '页数',
                                state.isLoadingPageCount && state.displayPageCount == 0
                                    ? '计算中...'
                                    : '${state.displayPageCount}',
                            ),
                            _buildInfoRow(context, '章节', '${detail.episodeCount}'),
                            if (detail.pubDate.isNotEmpty)
                                _buildInfoRow(context, '日期', detail.pubDate),
                            if (detail.views.isNotEmpty)
                                _buildInfoRow(context, '浏览', detail.views),
                        ],
                    ),
                ),
            ],
        );
    }

    /// 构建信息行
    Widget _buildInfoRow(BuildContext context, String label, String value)
    {
        return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
                children: [
                    Text(
                        '$label: ',
                        style: TextStyle(
                            fontSize: 13,
                            color: context.appColors.textSecondary,
                        ),
                    ),
                    Flexible(
                        child: Text(
                            value,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.appColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                        ),
                    ),
                ],
            ),
        );
    }
}

/// 构建标签流式布局
Widget buildDetailTags(BuildContext context, List<String> tags)
{
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((tag) =>
            Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                ),
                decoration: BoxDecoration(
                    color: context.appColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                    tag,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.textSecondary,
                    ),
                ),
            ),
        ).toList(),
    );
}

/// 构建简介区块
Widget buildDetailDescription(BuildContext context, String description)
{
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
                '简介',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.textPrimary,
                ),
            ),
            const SizedBox(height: 8),
            Text(
                description,
                style: TextStyle(
                    fontSize: 14,
                    color: context.appColors.textSecondary,
                    height: 1.6,
                ),
            ),
        ],
    );
}
