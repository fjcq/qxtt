import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/jm/jm_entity.dart';
import '../data/models/download_task_model.dart';
import '../providers/search_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/episode_list.dart';
import '../widgets/loading_widget.dart';
import '../widgets/error_widget.dart';
import 'album_detail_download_bar.dart';
import 'album_detail_favorite_button.dart';
import 'album_detail_info_section.dart';

/// 本子详情页
///
/// 下载功能已合并进本页：AppBar 下载按钮状态化（发起/暂停/继续/重试）、
/// 章节列表每行独立进度条、底部下载状态栏（整本进度 + 暂停/继续/取消），
/// 下载页仍保留作为全局任务管理入口
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

        // 本子关联的下载任务（整本 + 各单章）
        final downloadTasks = ref.watch(albumDownloadTasksProvider(albumId));
        final albumTask = firstAlbumTask(downloadTasks);

        return Scaffold(
            appBar: AppBar(
                title: const Text('详情'),
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                ),
                actions: [
                    if (state.detail != null)
                        AlbumDetailFavoriteButton(
                            albumId: albumId,
                            // 以详情接口返回的 is_favorite 初始化收藏状态，
                            // 使从收藏页等任意入口进入时状态与真实收藏夹一致
                            initiallyFavorite: state.detail!.isFavorite,
                        ),
                    if (state.detail != null)
                        _DownloadAppBarButton(
                            albumTask: albumTask,
                            onDownload: () =>
                                _downloadAlbum(context, ref, state.detail!),
                        ),
                ],
            ),
            body: _buildBody(context, ref, state),
            bottomNavigationBar: state.detail != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        // 整本下载活跃/可恢复时：顶部显示下载状态栏（进度 + 操作）
                        if (albumTask != null && !albumTask.isFinal)
                            AlbumDetailDownloadBar(task: albumTask),
                        // 原有按钮行（继续阅读 / 本地阅读 / 下载整本）
                        _buildBottomBar(context, ref, state),
                    ],
                )
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
                    AlbumDetailInfoSection(state: state),
                    const SizedBox(height: 16),
                    // 标签
                    if (detail.tags.isNotEmpty) buildDetailTags(context, detail.tags),
                    const SizedBox(height: 16),
                    // 简介
                    if (detail.description.isNotEmpty)
                        buildDetailDescription(context, detail.description),
                    const SizedBox(height: 16),
                    // 章节列表
                    if (detail.episodes.isNotEmpty)
                        _buildEpisodes(context, ref, detail),
                ],
            ),
        );
    }

    /// 跳转阅读器：已下载章节走本地阅读器（离线可读），未下载走在线阅读器
    void _pushReader(BuildContext context, WidgetRef ref, String photoId)
    {
        final downloaded = ref.read(downloadedEpisodesProvider(albumId));
        context.push(
            downloaded.contains(photoId)
                ? '/reader/$photoId'
                : '/reader/online/$photoId',
        );
    }

    /// 构建章节列表
    Widget _buildEpisodes(BuildContext context, WidgetRef ref, AlbumDetail detail)
    {
        // 监听本子已下载的章节 ID 集合，用于隐藏对应下载按钮
        final downloadedPhotoIds = ref.watch(downloadedEpisodesProvider(albumId));
        // 监听本子关联的下载任务，合并章节级进度（整本优先，单章补充）
        final downloadTasks = ref.watch(albumDownloadTasksProvider(albumId));
        final albumTask = firstAlbumTask(downloadTasks);
        final mergedProgress = mergeChapterProgress(downloadTasks);
        // 等待状态：整本任务活跃但章节进度尚未就绪（正在获取详情）
        final waitingForDetail = albumTask != null &&
            albumTask.isActive &&
            albumTask.chapterProgress.isEmpty;

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
                    chapterProgress: mergedProgress,
                    hasActiveTask: waitingForDetail,
                    onDownload: (episode) =>
                        _downloadPhoto(context, ref, episode, detail),
                    onRead: (episode) => _pushReader(context, ref, episode.photoId),
                ),
            ],
        );
    }

    /// 构建底部操作栏（有阅读进度时显示"继续阅读"；下载中显示整本状态栏）
    Widget _buildBottomBar(BuildContext context, WidgetRef ref, AlbumDetailState state)
    {
        final detail = state.detail!;
        final canResume = state.hasReadProgress;
        final history = state.history;

        // 已下载章节集合，用于本地阅读路由与整本下载状态判断
        final downloaded = ref.watch(downloadedEpisodesProvider(albumId));
        // 本子关联任务：整本下载活跃时右键禁用（状态栏已提供整本级操作）
        final downloadTasks = ref.watch(albumDownloadTasksProvider(albumId));
        final albumTask = firstAlbumTask(downloadTasks);
        // 整本（所有章节）均已下载时，底部按钮切换为"本地阅读"
        final allDownloaded =
            detail.episodes.isNotEmpty && downloaded.length >= detail.episodes.length;

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

        final albumActive = albumTask != null && albumTask.isActive;
        // 右侧按钮文案：整本下载中显示进度百分比（禁用），否则按下载/阅读状态切换
        String rightLabel = allDownloaded ? '本地阅读' : '下载整本';
        if (albumActive)
        {
            final progress = albumTask.progress;
            rightLabel = '下载中 ${(progress * 100).toStringAsFixed(0)}%';
        }

        return SafeArea(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                    children: [
                        // 继续阅读（仅在有有效进度时显示），已下载章节自动走本地阅读器
                        if (canResume) ...[
                            Expanded(
                                child: ElevatedButton.icon(
                                    onPressed: ()
                                    {
                                        final photoId = history!.lastReadPhotoId;
                                        if (photoId != null && photoId.isNotEmpty)
                                        {
                                            _pushReader(context, ref, photoId);
                                        }
                                    },
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
                        // 右侧按钮：整本已下载 → "本地阅读"；整本下载中 → "下载中…"（禁用）；
                        // 否则 → "下载整本"（补齐缺失章节）
                        Expanded(
                            child: ElevatedButton(
                                onPressed: albumActive
                                    ? null
                                    : ()
                                    {
                                        if (allDownloaded)
                                        {
                                            final resume = canResume
                                                ? (history!.lastReadPhotoId ?? '')
                                                : '';
                                            final target = resume.isNotEmpty
                                                ? resume
                                                : detail.episodes.first.photoId;
                                            context.push('/reader/$target');
                                        }
                                        else
                                        {
                                            _downloadAlbum(context, ref, detail);
                                        }
                                    },
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 48),
                                ),
                                child: Text(rightLabel),
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

/// AppBar 下载按钮：随整本任务状态切换图标与行为
///
/// - 无整本任务 → 下载图标，点击发起整本下载
/// - running/pending → 进度环，点击暂停
/// - paused → 继续图标，点击继续
/// - failed/cancelled → 错误图标，点击重试
/// 仅单章任务存在时保持下载图标（整本可另发起）
class _DownloadAppBarButton extends ConsumerWidget
{
    /// 整本下载任务（无则显示普通下载图标）
    final DownloadTaskModel? albumTask;

    /// 发起整本下载回调
    final VoidCallback onDownload;

    const _DownloadAppBarButton({
        required this.albumTask,
        required this.onDownload,
    });

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final task = albumTask;
        // 无整本任务（或已终结）：普通下载入口
        if (task == null || task.isFinal)
        {
            return IconButton(
                icon: const Icon(Icons.download),
                tooltip: '下载整本',
                onPressed: onDownload,
            );
        }
        final notifier = ref.read(downloadProvider.notifier);
        // 运行中：显示进度环，点击暂停
        if (task.isActive)
        {
            return IconButton(
                tooltip: '暂停下载',
                icon: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        value: task.totalImages > 0
                            ? task.progress.clamp(0.0, 1.0)
                            : null,
                        strokeWidth: 2.5,
                    ),
                ),
                onPressed: () => notifier.pauseTask(task.taskId),
            );
        }
        // 已暂停：点击继续
        if (task.isPaused)
        {
            return IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: '继续下载',
                onPressed: () => notifier.resumeTask(task.taskId),
            );
        }
        // 失败/取消：点击重试
        return IconButton(
            icon: const Icon(Icons.error_outline),
            color: context.appColors.error,
            tooltip: '重试下载',
            onPressed: () => notifier.retryTask(task.taskId),
        );
    }
}
