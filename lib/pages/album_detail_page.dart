import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../core/jm/jm_entity.dart';
import '../core/jm/jm_image.dart';
import '../providers/search_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/favorite_provider.dart';
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

        // 确保书架数据已加载，以便正确显示已下载章节状态
        final libraryState = ref.watch(libraryProvider);
        if (!libraryState.isLoading && libraryState.albums.isEmpty)
        {
            Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
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
                        _FavoriteButton(albumId: albumId),
                    if (state.detail != null)
                        IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _downloadAlbum(context, ref, state.detail!),
                        ),
                ],
            ),
            body: _buildBody(context, ref, state),
            bottomNavigationBar: state.detail != null
                ? _buildBottomBar(context, ref, state)
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

        return _buildDetail(context, ref, state);
    }

    /// 构建详情内容
    Widget _buildDetail(BuildContext context, WidgetRef ref, AlbumDetailState state)
    {
        final detail = state.detail!;
        return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // 封面和信息
                    _buildInfoSection(context, state, ref),
                    const SizedBox(height: 16),
                    // 标签
                    if (detail.tags.isNotEmpty) _buildTags(context, detail.tags),
                    const SizedBox(height: 16),
                    // 简介
                    if (detail.description.isNotEmpty) _buildDescription(context, detail.description),
                    const SizedBox(height: 16),
                    // 章节列表
                    if (detail.episodes.isNotEmpty)
                        _buildEpisodes(context, ref, detail),
                ],
            ),
        );
    }

    /// 构建信息区域
    Widget _buildInfoSection(BuildContext context, AlbumDetailState state, WidgetRef ref)
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

    /// 构建标签
    Widget _buildTags(BuildContext context, List<String> tags)
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

    /// 构建简介
    Widget _buildDescription(BuildContext context, String description)
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

    /// 构建章节列表
    Widget _buildEpisodes(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        // 监听本子已下载的章节 ID 集合，用于隐藏对应下载按钮
        final downloadedPhotoIds = ref.watch(downloadedEpisodesProvider(albumId));

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                    '章节列表',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.appColors.textPrimary,
                    ),
                ),
                const SizedBox(height: 8),
                EpisodeList(
                    episodes: detail.episodes,
                    downloadedPhotoIds: downloadedPhotoIds,
                    onDownload: (episode) =>
                        _downloadPhoto(context, ref, episode, detail),
                    onRead: (episode) => context.push('/reader/online/${episode.photoId}'),
                ),
            ],
        );
    }

    /// 构建底部操作栏（有阅读进度时显示"继续阅读"+"下载整本"）
    Widget _buildBottomBar(BuildContext context, WidgetRef ref, AlbumDetailState state)
    {
        final detail = state.detail!;
        final canResume = state.hasReadProgress;
        final history = state.history;

        // 继续阅读按钮文案：定位到上次阅读的章节名（找不到章节时仅显示"继续阅读"）
        String resumeLabel = '继续阅读';
        if (canResume)
        {
            for (final episode in detail.episodes)
            {
                if (episode.photoId == history!.lastReadPhotoId)
                {
                    resumeLabel = '继续阅读 · ${episode.name}';
                    break;
                }
            }
        }

        return SafeArea(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                    children: [
                        // 继续阅读（仅在有有效进度时显示）
                        if (canResume) ...[
                            Expanded(
                                child: ElevatedButton.icon(
                                    onPressed: () => context.push(
                                        '/reader/online/${history!.lastReadPhotoId}',
                                    ),
                                    icon: const Icon(Icons.play_arrow, size: 20),
                                    label: Text(
                                        resumeLabel,
                                        overflow: TextOverflow.ellipsis,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 48),
                                    ),
                                ),
                            ),
                            const SizedBox(width: 12),
                        ],
                        // 下载整本
                        Expanded(
                            child: ElevatedButton(
                                onPressed: () => _downloadAlbum(context, ref, detail),
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 48),
                                ),
                                child: const Text('下载整本'),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 下载整本
    Future<void> _downloadAlbum(BuildContext context, WidgetRef ref, AlbumDetail detail) async
    {
        final result = await ref.read(downloadProvider.notifier).createAndStartDownload(
            'album',
            detail.albumId,
            title: detail.name,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    result.isNewlyCreated
                        ? '已添加下载任务: ${detail.name}'
                        : '该本子已在下载队列中,无需重复添加',
                ),
            ),
        );
    }

    /// 下载单章
    Future<void> _downloadPhoto(BuildContext context, WidgetRef ref, Episode episode, AlbumDetail detail) async
    {
        final result = await ref.read(downloadProvider.notifier).createAndStartDownload(
            'photo',
            episode.photoId,
            albumId: detail.albumId,
            albumTitle: detail.name,
            episodeIndex: episode.index,
            episodeName: episode.name,
            title: '${detail.name} - ${episode.name}',
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    result.isNewlyCreated
                        ? '已添加下载任务: ${episode.name}'
                        : '该章节已在下载队列中,无需重复添加',
                ),
            ),
        );
    }
}

/// 详情页收藏按钮
///
/// 服务端收藏接口为 Toggle 语义（已收藏则取消，未收藏则添加），
/// 本按钮以局部状态跟踪最近一次操作结果：实心=已收藏，空心=未收藏/未知。
/// 未登录时点击引导去设置页登录。
class _FavoriteButton extends ConsumerStatefulWidget
{
    /// 本子 ID
    final String albumId;

    const _FavoriteButton({required this.albumId});

    @override
    ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton>
{
    /// 收藏状态：null=未知，true=已收藏，false=未收藏
    bool? _favActive;

    /// 是否正在请求
    bool _busy = false;

    /// 切换收藏状态
    Future<void> _toggle() async
    {
        if (_busy) return;

        // 未登录引导：先确保启动时的会话恢复已完成（幂等），再判断登录态
        if (!ref.read(authProvider).loggedIn)
        {
            await ref.read(authProvider.notifier).ensureRestored();
        }
        if (!mounted) return;
        if (!ref.read(authProvider).loggedIn)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先在设置页登录账号后再收藏')),
            );
            return;
        }

        setState(() => _busy = true);
        try
        {
            final type = await ref
                .read(favoriteProvider.notifier)
                .toggle(widget.albumId);
            if (!mounted) return;
            setState(()
            {
                _favActive = type == 'add';
                _busy = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(type == 'add' ? '已加入收藏' : '已取消收藏'),
                ),
            );
        }
        catch (e)
        {
            if (!mounted) return;
            setState(() => _busy = false);
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('收藏操作失败: $e')),
            );
        }
    }

    @override
    Widget build(BuildContext context)
    {
        return IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(_favActive == true
                    ? Icons.favorite
                    : Icons.favorite_border),
            color: _favActive == true ? context.appColors.error : null,
            tooltip: '收藏',
            onPressed: _toggle,
        );
    }
}
