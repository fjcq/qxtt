import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../core/jm/jm_client.dart';
import '../core/jm/jm_entity.dart';
import '../providers/search_provider.dart';
import '../providers/download_provider.dart';
import '../providers/browse_history_provider.dart';
import '../data/database/browse_history_dao.dart';
import '../theme/app_colors.dart';
import '../widgets/episode_list.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';

/// 本子详情页
class AlbumDetailPage extends ConsumerWidget
{
    /// 本子 ID
    final String albumId;

    const AlbumDetailPage({
        super.key,
        required this.albumId,
    });

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final state = ref.watch(albumDetailProvider(albumId));

        // 首次加载
        if (state.detail == null && !state.isLoading && state.error == null)
        {
            Future.microtask(() =>
                ref.read(albumDetailProvider(albumId).notifier).loadDetail(albumId),
            );
        }

        if (state.detail != null && !state.isLoading && state.error == null)
        {
            // 记录浏览历史
            Future.microtask(() =>
                ref.read(browseHistoryProvider.notifier).addHistory(BrowseHistoryModel()
                    ..albumId = state.detail!.albumId
                    ..title = state.detail!.name
                    ..coverUrl = JmClient().getAlbumCoverUrl(state.detail!.albumId)
                    ..author = state.detail!.author
                    ..browsedAt = DateTime.now().toIso8601String()
                    ..lastReadPage = 0,
                ),
            );
        }

        return Scaffold(
            appBar: AppBar(
                title: const Text('详情'),
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                ),
                actions: [
                    if (state.detail != null)
                        IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _downloadAlbum(context, ref, state.detail!),
                        ),
                ],
            ),
            body: _buildBody(context, ref, state),
            bottomNavigationBar: state.detail != null
                ? _buildBottomBar(context, ref, state.detail!)
                : null,
        );
    }

    /// 构建主体
    Widget _buildBody(BuildContext context, WidgetRef ref, AlbumDetailState state)
    {
        if (state.isLoading)
        {
            return const LoadingWidget(message: '加载详情中...');
        }

        if (state.error != null)
        {
            return AppErrorWidget(
                message: state.error!,
                onRetry: () =>
                    ref.read(albumDetailProvider(albumId).notifier).loadDetail(albumId),
            );
        }

        if (state.detail == null) return const SizedBox.shrink();

        return _buildDetail(context, ref, state.detail!);
    }

    /// 构建详情内容
    Widget _buildDetail(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // 封面和信息
                    _buildInfoSection(detail),
                    const SizedBox(height: 16),
                    // 标签
                    if (detail.tags.isNotEmpty) _buildTags(detail.tags),
                    const SizedBox(height: 16),
                    // 简介
                    if (detail.description.isNotEmpty) _buildDescription(detail.description),
                    const SizedBox(height: 16),
                    // 章节列表
                    if (detail.episodes.isNotEmpty)
                        _buildEpisodes(context, ref, detail),
                ],
            ),
        );
    }

    /// 构建信息区域
    Widget _buildInfoSection(AlbumDetail detail)
    {
        final client = JmClient();
        final coverUrl = client.getAlbumCoverUrl(detail.albumId);

        return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // 封面
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                        imageUrl: coverUrl,
                        width: 120,
                        height: 160,
                        fit: BoxFit.cover,
                        httpHeaders: const {
                            'Referer': 'https://www.cdnhjk.net/',
                        },
                        placeholder: (_, __) => Container(
                            width: 120,
                            height: 160,
                            color: AppColors.surfaceVariant,
                            child: const Center(
                                child: Icon(Icons.image, color: AppColors.textDisabled),
                            ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                            width: 120,
                            height: 160,
                            color: AppColors.surfaceVariant,
                            child: const Center(
                                child: Icon(Icons.broken_image, color: AppColors.textDisabled),
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
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                ),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow('作者', detail.author),
                            _buildInfoRow('页数', '${detail.pageCount}'),
                            _buildInfoRow('章节', '${detail.episodeCount}'),
                            if (detail.pubDate.isNotEmpty)
                                _buildInfoRow('日期', detail.pubDate),
                            if (detail.views.isNotEmpty)
                                _buildInfoRow('浏览', detail.views),
                        ],
                    ),
                ),
            ],
        );
    }

    /// 构建信息行
    Widget _buildInfoRow(String label, String value)
    {
        return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
                children: [
                    Text(
                        '$label: ',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                        ),
                    ),
                    Flexible(
                        child: Text(
                            value,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                        ),
                    ),
                ],
            ),
        );
    }

    /// 构建标签
    Widget _buildTags(List<String> tags)
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
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                        tag,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                        ),
                    ),
                ),
            ).toList(),
        );
    }

    /// 构建简介
    Widget _buildDescription(String description)
    {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text(
                    '简介',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                    ),
                ),
                const SizedBox(height: 8),
                Text(
                    description,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.6,
                    ),
                ),
            ],
        );
    }

    /// 构建章节列表
    Widget _buildEpisodes(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text(
                    '章节列表',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                    ),
                ),
                const SizedBox(height: 8),
                EpisodeList(
                    episodes: detail.episodes,
                    onDownload: (episode) => _downloadPhoto(context, ref, episode, detail.name),
                    onRead: (episode) => context.push('/reader/${episode.photoId}'),
                ),
            ],
        );
    }

    /// 构建底部操作栏
    Widget _buildBottomBar(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        return SafeArea(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ElevatedButton(
                    onPressed: () => _downloadAlbum(context, ref, detail),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('下载整本'),
                ),
            ),
        );
    }

    /// 下载整本
    void _downloadAlbum(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        ref.read(downloadProvider.notifier).createAndStartDownload(
            'album',
            detail.albumId,
            title: detail.name,
        );
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加下载任务: ${detail.name}')),
        );
    }

    /// 下载单章
    void _downloadPhoto(BuildContext context, WidgetRef ref, Episode episode, String albumTitle)
    {
        ref.read(downloadProvider.notifier).createAndStartDownload(
            'photo',
            episode.photoId,
            title: '$albumTitle - ${episode.name}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加下载任务: ${episode.name}')),
        );
    }
}
