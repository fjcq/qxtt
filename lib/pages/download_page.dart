import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../data/models/download_task_model.dart';
import '../data/models/library_album_model.dart';
import '../theme/app_colors.dart';
import '../widgets/download_progress.dart';
import '../widgets/loading_widget.dart';

/// 下载页（含已下载和下载中双Tab）
class DownloadPage extends ConsumerStatefulWidget
{
    const DownloadPage({super.key});

    @override
    ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with SingleTickerProviderStateMixin
{
    late TabController _tabController;
    bool _isEditMode = false;
    final Set<String> _selectedIds = {};

    @override
    void initState()
    {
        super.initState();
        _tabController = TabController(length: 2, vsync: this);
        Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
    }

    @override
    void dispose()
    {
        _tabController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            appBar: AppBar(
                title: const Text('下载'),
                actions: _buildActions(),
                bottom: TabBar(
                    controller: _tabController,
                    tabs: const [
                        Tab(text: '已下载'),
                        Tab(text: '下载中'),
                    ],
                    labelColor: AppColors.accent,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.accent,
                ),
            ),
            body: TabBarView(
                controller: _tabController,
                children: [
                    _buildLibraryTab(),
                    _buildDownloadTab(),
                ],
            ),
        );
    }

    /// 构建操作按钮
    List<Widget> _buildActions()
    {
        final actions = <Widget>[];

        if (_tabController.index == 0)
        {
            // 已下载Tab的操作
            actions.add(
                IconButton(
                    icon: Icon(_isEditMode ? Icons.check : Icons.edit),
                    onPressed: () => setState(() => _isEditMode = !_isEditMode),
                ),
            );
            actions.add(
                IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshLibrary,
                ),
            );
        }
        else
        {
            // 下载中Tab的操作
            actions.add(
                PopupMenuButton<String>(
                    onSelected: (value) async
                    {
                        if (value == 'clear')
                        {
                            await ref.read(downloadProvider.notifier).clearCompleted();
                        }
                        else if (value == 'refresh')
                        {
                            await ref.read(downloadProvider.notifier).refresh();
                        }
                    },
                    itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'refresh',
                            child: Text('刷新'),
                        ),
                        const PopupMenuItem(
                            value: 'clear',
                            child: Text('清除已完成'),
                        ),
                    ],
                ),
            );
        }

        return actions;
    }

    /// 构建已下载Tab（原书架功能）
    Widget _buildLibraryTab()
    {
        final state = ref.watch(libraryProvider);

        if (state.isLoading && state.albums.isEmpty)
        {
            return const LoadingWidget(message: '加载中...');
        }

        if (state.albums.isEmpty)
        {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.library_books,
                            size: 64,
                            color: AppColors.textDisabled.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                            '暂无已下载的漫画',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                            ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            '下载漫画后会自动出现在这里',
                            style: TextStyle(
                                color: AppColors.textDisabled,
                                fontSize: 13,
                            ),
                        ),
                    ],
                ),
            );
        }

        return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.6,
            ),
            itemCount: state.albums.length,
            itemBuilder: (context, index)
            {
                return _buildAlbumCard(state.albums[index]);
            },
        );
    }

    /// 构建书架卡片
    Widget _buildAlbumCard(LibraryAlbumModel album)
    {
        final isSelected = _selectedIds.contains(album.albumId);

        return GestureDetector(
            onLongPress: ()
            {
                setState(() => _isEditMode = true);
                _toggleSelect(album.albumId);
            },
            onTap: ()
            {
                if (_isEditMode)
                {
                    _toggleSelect(album.albumId);
                }
                else
                {
                    context.push('/album/${album.albumId}');
                }
            },
            child: Stack(
                children: [
                    Container(
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: AppColors.accent, width: 2)
                                : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(
                                    child: Container(
                                        color: AppColors.surfaceVariant,
                                        child: Center(
                                            child: album.coverPath.isNotEmpty
                                                ? Image.file(
                                                    File(album.coverPath),
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    errorBuilder: (_, __, ___) =>
                                                        const Icon(
                                                            Icons.broken_image,
                                                            color: AppColors.textDisabled,
                                                        ),
                                                )
                                                : const Icon(
                                                    Icons.image_outlined,
                                                    color: AppColors.textDisabled,
                                                    size: 32,
                                                ),
                                        ),
                                    ),
                                ),
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
                                                    fontSize: 12,
                                                    color: AppColors.textPrimary,
                                                ),
                                            ),
                                            if (album.lastReadPage > 0)
                                                Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Text(
                                                        '读到第 ${album.lastReadPage} 页',
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            color: AppColors.accent,
                                                        ),
                                                    ),
                                                ),
                                        ],
                                    ),
                                ),
                            ],
                        ),
                    ),
                    // 编辑模式选中标记
                    if (_isEditMode)
                        Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.surfaceVariant,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 16, color: AppColors.background)
                                    : null,
                            ),
                        ),
                ],
            ),
        );
    }

    /// 构建下载中Tab
    Widget _buildDownloadTab()
    {
        final state = ref.watch(downloadProvider);

        if (state.tasks.isEmpty)
        {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.download_outlined,
                            size: 64,
                            color: AppColors.textDisabled.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                            '暂无下载任务',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                            ),
                        ),
                    ],
                ),
            );
        }

        return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index)
            {
                return _buildTaskCard(state.tasks[index]);
            },
        );
    }

    /// 构建任务卡片
    Widget _buildTaskCard(DownloadTaskModel task)
    {
        final statusColor = _getStatusColor(task.status);
        final statusText = _getStatusText(task.status);

        return Dismissible(
            key: Key(task.taskId),
            direction: DismissDirection.endToStart,
            background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: AppColors.error,
                child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) =>
                ref.read(downloadProvider.notifier).deleteTask(task.taskId),
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // 标题和状态
                        Row(
                            children: [
                                Expanded(
                                    child: Text(
                                        task.title ?? task.jmId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                        ),
                                    ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                        statusText,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: statusColor,
                                            fontWeight: FontWeight.w500,
                                        ),
                                    ),
                                ),
                            ],
                        ),
                        const SizedBox(height: 8),
                        // 进度条
                        DownloadProgress(
                            progress: task.progress,
                            statusText: task.message,
                            countText: '${task.currentImage}/${task.totalImages}',
                            speedText: task.speed,
                        ),
                        // 操作按钮
                        if (task.status == 'running' || task.status == 'pending')
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: () =>
                                        ref.read(downloadProvider.notifier).cancelTask(task.taskId),
                                    child: const Text('取消'),
                                ),
                            ),
                    ],
                ),
            ),
        );
    }

    /// 切换选中
    void _toggleSelect(String albumId)
    {
        setState(()
        {
            if (_selectedIds.contains(albumId))
            {
                _selectedIds.remove(albumId);
            }
            else
            {
                _selectedIds.add(albumId);
            }
        });
    }

    /// 刷新书架
    Future<void> _refreshLibrary() async
    {
        await ref.read(libraryProvider.notifier).refreshLibrary('');
    }

    /// 获取状态颜色
    Color _getStatusColor(String status)
    {
        switch (status)
        {
            case 'completed':
                return AppColors.success;
            case 'running':
                return AppColors.accent;
            case 'failed':
                return AppColors.error;
            case 'cancelled':
                return AppColors.textDisabled;
            default:
                return AppColors.textSecondary;
        }
    }

    /// 获取状态文本
    String _getStatusText(String status)
    {
        switch (status)
        {
            case 'pending':
                return '等待中';
            case 'running':
                return '下载中';
            case 'completed':
                return '已完成';
            case 'failed':
                return '失败';
            case 'cancelled':
                return '已取消';
            default:
                return status;
        }
    }
}
