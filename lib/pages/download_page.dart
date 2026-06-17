import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/library_album_model.dart';
import '../providers/config_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import '../utils/directory_opener.dart';
import '../utils/library_storage.dart';
import '../widgets/download_task_tile.dart';
import '../widgets/downloaded_album_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/sort_filter_bar.dart';
import '../widgets/storage_summary_bar.dart';

/// 下载页（含已下载/下载中/已完成/失败四个分页）
/// 重构点：
/// - 顶部展示存储信息
/// - 已下载分页支持排序、搜索、编辑模式、批量删除
/// - 下载中分页按状态分组（active/completed/failed），支持单条与批量操作
class DownloadPage extends ConsumerStatefulWidget
{
    const DownloadPage({super.key});

    @override
    ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with TickerProviderStateMixin
{
    /// 当前 Tab 索引
    static const int tabLibrary = 0;
    static const int tabDownload = 1;

    late final TabController _tabController;

    /// 是否处于编辑模式（仅对已下载分页生效）
    bool _isEditMode = false;

    /// 已调度过补封面任务的 albumId，避免重复刷新
    final Set<String> _coverRefreshScheduled = {};

    /// 延迟刷新缺失封面：仅对当前可见的、且无有效 coverPath 的本子触发
    void _scheduleLazyCoverRefresh(List<LibraryAlbumModel> visible)
    {
        final pending = visible
            .where((a) =>
                a.coverPath.isEmpty || !File(a.coverPath).existsSync())
            .where((a) => !_coverRefreshScheduled.contains(a.albumId))
            .toList();
        if (pending.isEmpty) return;
        for (final album in pending)
        {
            _coverRefreshScheduled.add(album.albumId);
        }
        WidgetsBinding.instance.addPostFrameCallback((_)
        {
            if (!mounted) return;
            for (final album in pending)
            {
                ref.read(libraryProvider.notifier).refreshCover(album);
            }
        });
    }

    /// 已下载分页：当前选中的 albumId
    final Set<String> _selectedAlbumIds = {};

    /// 已下载分页：当前选中的 taskId（来自下载中 Tab 的 completed 任务）
    final Set<String> _selectedTaskIds = {};

    /// 下载中分页：批量操作模式（true 时显示多选）
    bool _taskEditMode = false;

    @override
    void initState()
    {
        super.initState();
        _tabController = TabController(length: 2, vsync: this);
        _tabController.addListener(_onTabChanged);
        // 首次进入加载书架
        Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
    }

    @override
    void dispose()
    {
        _tabController.removeListener(_onTabChanged);
        _tabController.dispose();
        super.dispose();
    }

    /// Tab 切换回调
    void _onTabChanged()
    {
        if (_tabController.indexIsChanging) return;
        if (!mounted) return;
        // 切换 Tab 时自动退出编辑模式与多选
        if (_isEditMode || _taskEditMode)
        {
            setState(()
            {
                _isEditMode = false;
                _taskEditMode = false;
                _selectedAlbumIds.clear();
                _selectedTaskIds.clear();
            });
        }
        else
        {
            setState(() {});
        }
        if (_tabController.index == tabLibrary)
        {
            // 切回已下载 Tab 时确保数据最新
            Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
        }
    }

    @override
    Widget build(BuildContext context)
    {
        // 监听下载完成事件：弹 SnackBar 提示用户
        ref.listen<DownloadState>(downloadProvider, (prev, next)
        {
            if (prev == null) return;
            if (next.completionCounter > prev.completionCounter)
            {
                final task = next.lastCompletedTask;
                if (task == null) return;
                final title = task.title != null && task.title!.isNotEmpty
                    ? task.title!
                    : task.jmId;
                _showCompletionSnack(title, task.totalImages);
            }
        });

        return Scaffold(
            appBar: _buildAppBar(),
            body: TabBarView(
                controller: _tabController,
                children: [
                    _buildLibraryTab(),
                    _buildDownloadTab(),
                ],
            ),
            // 编辑模式底部操作栏
            bottomNavigationBar: _buildBottomBar(),
        );
    }

    /// 顶部导航栏
    PreferredSizeWidget _buildAppBar()
    {
        final showLibraryActions = _tabController.index == tabLibrary;
        final showDownloadActions = _tabController.index == tabDownload;
        return AppBar(
            title: Text(_isEditMode
                ? '已选择 ${_selectedAlbumIds.length} 项'
                : (_taskEditMode
                    ? '已选择 ${_selectedTaskIds.length} 项'
                    : '下载')),
            actions: showLibraryActions
                ? _buildLibraryActions()
                : (showDownloadActions ? _buildDownloadActions() : const []),
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
        );
    }

    /// 已下载分页操作按钮
    List<Widget> _buildLibraryActions()
    {
        if (_isEditMode)
        {
            return [
                IconButton(
                    tooltip: '全选',
                    icon: const Icon(Icons.select_all),
                    onPressed: _toggleSelectAll,
                ),
                IconButton(
                    tooltip: '反选',
                    icon: const Icon(Icons.flip),
                    onPressed: _invertSelection,
                ),
                IconButton(
                    tooltip: '退出编辑',
                    icon: const Icon(Icons.close),
                    onPressed: _exitEditMode,
                ),
            ];
        }
        return [
            IconButton(
                tooltip: '管理',
                icon: const Icon(Icons.checklist_rtl),
                onPressed: _enterEditMode,
            ),
            PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: _handleLibraryMenu,
                color: AppColors.surface,
                itemBuilder: (context)
                {
                    return const [
                        PopupMenuItem(
                            value: 'open_dir',
                            child: Row(
                                children: [
                                    Icon(Icons.folder_open, size: 18, color: AppColors.textSecondary),
                                    SizedBox(width: 8),
                                    Text('打开下载目录'),
                                ],
                            ),
                        ),
                        PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                                children: [
                                    Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                                    SizedBox(width: 8),
                                    Text('刷新占用统计'),
                                ],
                            ),
                        ),
                        PopupMenuItem(
                            value: 'orphan',
                            child: Row(
                                children: [
                                    Icon(Icons.cleaning_services, size: 18, color: AppColors.textSecondary),
                                    SizedBox(width: 8),
                                    Text('清理孤儿文件夹'),
                                ],
                            ),
                        ),
                        PopupMenuItem(
                            value: 'clear',
                            child: Row(
                                children: [
                                    Icon(Icons.delete_forever, size: 18, color: AppColors.error),
                                    SizedBox(width: 8),
                                    Text('清空所有下载', style: TextStyle(color: AppColors.error)),
                                ],
                            ),
                        ),
                    ];
                },
            ),
        ];
    }

    /// 下载中分页操作按钮
    List<Widget> _buildDownloadActions()
    {
        if (_taskEditMode)
        {
            return [
                IconButton(
                    tooltip: '全选',
                    icon: const Icon(Icons.select_all),
                    onPressed: _toggleSelectAllTasks,
                ),
                IconButton(
                    tooltip: '反选',
                    icon: const Icon(Icons.flip),
                    onPressed: _invertTaskSelection,
                ),
                IconButton(
                    tooltip: '退出',
                    icon: const Icon(Icons.close),
                    onPressed: _exitTaskEditMode,
                ),
            ];
        }
        return [
            IconButton(
                tooltip: '批量管理',
                icon: const Icon(Icons.checklist_rtl),
                onPressed: _enterTaskEditMode,
            ),
            PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: _handleDownloadMenu,
                color: AppColors.surface,
                itemBuilder: (context)
                {
                    final state = ref.read(downloadProvider);
                    final hasFailed = state.failedCount > 0;
                    final hasActive = state.activeCount > 0;
                    return [
                        const PopupMenuItem(
                            value: 'open_dir',
                            child: Row(
                                children: [
                                    Icon(Icons.folder_open, size: 18, color: AppColors.textSecondary),
                                    SizedBox(width: 8),
                                    Text('打开下载目录'),
                                ],
                            ),
                        ),
                        if (hasFailed)
                            const PopupMenuItem(
                                value: 'retry_all',
                                child: Row(
                                    children: [
                                        Icon(Icons.refresh, size: 18, color: AppColors.warning),
                                        SizedBox(width: 8),
                                        Text('重试所有失败'),
                                    ],
                                ),
                            ),
                        if (hasActive)
                            const PopupMenuItem(
                                value: 'cancel_all',
                                child: Row(
                                    children: [
                                        Icon(Icons.block, size: 18, color: AppColors.textSecondary),
                                        SizedBox(width: 8),
                                        Text('全部取消'),
                                    ],
                                ),
                            ),
                        if (hasFailed)
                            const PopupMenuItem(
                                value: 'clear_failed',
                                child: Row(
                                    children: [
                                        Icon(Icons.delete_sweep, size: 18, color: AppColors.error),
                                        SizedBox(width: 8),
                                        Text('清除失败 / 已取消', style: TextStyle(color: AppColors.error)),
                                    ],
                                ),
                            ),
                    ];
                },
            ),
        ];
    }

    /// 编辑模式底部操作栏
    Widget? _buildBottomBar()
    {
        if (_tabController.index == tabLibrary && _isEditMode)
        {
            return _LibraryEditBar(
                count: _selectedAlbumIds.length,
                onDelete: _confirmBatchDeleteLibrary,
            );
        }
        if (_tabController.index == tabDownload && _taskEditMode)
        {
            return _TaskEditBar(
                count: _selectedTaskIds.length,
                onRetry: _confirmRetrySelectedTasks,
                onDelete: _confirmDeleteSelectedTasks,
            );
        }
        return null;
    }

    // ============================ 已下载分页 ============================

    /// 已下载分页主体
    Widget _buildLibraryTab()
    {
        final state = ref.watch(libraryProvider);
        final visible = state.visibleAlbums;

        return Column(
            children: [
                // 存储信息条
                StorageSummaryBar(
                    albumCount: state.albums.length,
                    episodeCount: state.totalDownloadedEpisodes,
                    totalBytes: state.totalSizeBytes,
                    fileCount: state.totalFileCount,
                    isLoading: state.isLoading,
                    onMoreTap: _openDownloadDirectory,
                ),
                // 排序 + 搜索条
                SortFilterBar(
                    sortType: state.sortType,
                    onSortChanged: (type)
                    {
                        ref.read(libraryProvider.notifier).setSortType(type);
                    },
                    keyword: state.keyword,
                    onKeywordChanged: (kw)
                    {
                        ref.read(libraryProvider.notifier).setKeyword(kw);
                    },
                    isEditing: _isEditMode,
                    onEnterEditMode: state.albums.isEmpty
                        ? null
                        : () => setState(() => _isEditMode = true),
                ),
                // 内容区
                Expanded(child: _buildLibraryContent(state, visible)),
            ],
        );
    }

    /// 已下载内容区
    Widget _buildLibraryContent(
        LibraryState state,
        List<LibraryAlbumModel> visible,
    )
    {
        if (state.isLoading && state.albums.isEmpty)
        {
            return const LoadingWidget(message: '加载中...');
        }
        if (state.albums.isEmpty)
        {
            // 启动一次空库刷新（触发后端拉取）
            _scheduleLazyCoverRefresh(visible);
            return _buildEmptyLibrary();
        }
        if (visible.isEmpty)
        {
            return _buildNoMatch();
        }
        // 触发缺失封面的本子在后台异步补全
        _scheduleLazyCoverRefresh(visible);
        return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.6,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index)
            {
                final album = visible[index];
                return DownloadedAlbumCard(
                    album: album,
                    isEditing: _isEditMode,
                    isSelected: _selectedAlbumIds.contains(album.albumId),
                    onTap: ()
                    {
                        if (_isEditMode)
                        {
                            _toggleSelectAlbum(album.albumId);
                        }
                        else
                        {
                            _openAlbumReader(album);
                        }
                    },
                    onLongPress: ()
                    {
                        // 长按直接进入编辑模式并选中
                        if (!_isEditMode)
                        {
                            setState(() => _isEditMode = true);
                        }
                        _toggleSelectAlbum(album.albumId);
                    },
                );
            },
        );
    }

    /// 空状态：完全没下载过
    Widget _buildEmptyLibrary()
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.library_books_outlined,
                            size: 72,
                            color: AppColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                            '书架空空如也',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                            ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            '去搜索感兴趣的漫画并下载吧',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 搜索/筛选无匹配
    Widget _buildNoMatch()
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.search_off,
                            size: 56,
                            color: AppColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                            '没有匹配的本子',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 跳转到阅读器
    void _openAlbumReader(LibraryAlbumModel album)
    {
        if (album.downloadedEpisodes.isEmpty)
        {
            // 没有下载章节，跳到本子详情
            context.push('/album/${album.albumId}');
            return;
        }
        // 优先从 lastReadAt 推断；若没有则取第一话
        final photoId = album.downloadedEpisodes.first;
        context.push('/reader/$photoId');
    }

    // ============================ 下载中分页 ============================

    /// 下载中分页主体
    Widget _buildDownloadTab()
    {
        final state = ref.watch(downloadProvider);
        if (state.tasks.isEmpty)
        {
            return _buildEmptyDownload();
        }
        return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: () async
            {
                await ref.read(downloadProvider.notifier).refresh();
            },
            child: _buildDownloadList(state),
        );
    }

    /// 下载中分页列表
    Widget _buildDownloadList(DownloadState state)
    {
        final grouped = state.grouped;
        final active = grouped[DownloadTaskGroup.active]!;
        final failed = grouped[DownloadTaskGroup.failed]!;

        return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
                if (active.isNotEmpty) ...[
                    _buildSectionHeader(
                        icon: Icons.cloud_download,
                        title: '正在下载',
                        count: active.length,
                        color: AppColors.accent,
                    ),
                    const SizedBox(height: 8),
                    ...active.map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DownloadTaskTile(
                                view: v,
                                onCancel: () =>
                                    ref.read(downloadProvider.notifier)
                                        .cancelTask(v.task.taskId),
                            ),
                        )),
                ],
                if (failed.isNotEmpty) ...[
                    if (active.isNotEmpty) const SizedBox(height: 4),
                    _buildSectionHeader(
                        icon: Icons.error_outline,
                        title: '失败 / 已取消',
                        count: failed.length,
                        color: AppColors.error,
                    ),
                    const SizedBox(height: 8),
                    ...failed.map((v) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DownloadTaskTile(
                                view: v,
                                isEditing: _taskEditMode,
                                isSelected:
                                    _selectedTaskIds.contains(v.task.taskId),
                                onTap: () => _taskEditMode
                                    ? _toggleSelectTask(v.task.taskId)
                                    : null,
                                onRetry: () =>
                                    ref.read(downloadProvider.notifier)
                                        .retryTask(v.task.taskId),
                                onDelete: () =>
                                    _confirmDeleteTask(v.task.taskId),
                            ),
                        )),
                ],
            ],
        );
    }

    /// 分组标题
    Widget _buildSectionHeader({
        required IconData icon,
        required String title,
        required int count,
        required Color color,
    })
    {
        return Row(
            children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                    title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                    ),
                ),
                const SizedBox(width: 6),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        '$count',
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w500,
                        ),
                    ),
                ),
            ],
        );
    }

    /// 空状态
    Widget _buildEmptyDownload()
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.cloud_off,
                            size: 64,
                            color: AppColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                            '暂无下载任务',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                            '到本子详情页发起下载',
                            style: TextStyle(
                                color: AppColors.textDisabled,
                                fontSize: 12,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    // ============================ 通用菜单回调 ============================

    /// 在系统文件管理器中打开下载根目录
    /// 读取配置中的 downloadDir，为空时回退到默认下载目录
    Future<void> _openDownloadDirectory() async
    {
        try
        {
            // 优先使用用户配置的下载目录
            final configured =
                ref.read(configProvider).config.downloadDir;
            final dir = await LibraryStorage.getDownloadDir(
                configured: configured,
            );
            final opened = await DirectoryOpener.open(dir);
            if (!mounted) return;
            if (!opened)
            {
                _showSnack('无法打开目录：$dir');
            }
        }
        catch (e)
        {
            if (!mounted) return;
            _showSnack('打开目录失败：$e');
        }
    }

    /// 已下载分页菜单
    void _handleLibraryMenu(String value) async
    {
        switch (value)
        {
            case 'open_dir':
                await _openDownloadDirectory();
                break;
            case 'refresh':
                await ref.read(libraryProvider.notifier).refreshAllSizeStats();
                if (mounted)
                {
                    _showSnack('已刷新占用统计');
                }
                break;
            case 'orphan':
                final removed =
                    await ref.read(libraryProvider.notifier).cleanupOrphanFolders();
                if (!mounted) return;
                _showSnack(removed == 0 ? '没有发现孤儿文件夹' : '已清理 $removed 个文件夹');
                break;
            case 'clear':
                await _confirmClearAllLibrary();
                break;
        }
    }

    /// 下载中分页菜单
    void _handleDownloadMenu(String value) async
    {
        switch (value)
        {
            case 'open_dir':
                await _openDownloadDirectory();
                break;
            case 'retry_all':
                final n = await ref.read(downloadProvider.notifier).retryAllFailed();
                if (mounted) _showSnack('已重试 $n 个任务');
                break;
            case 'cancel_all':
                final ok = await _confirm(
                    title: '全部取消',
                    message: '将取消所有正在下载或等待中的任务。\n未完成的本地部分文件保留。',
                    confirmText: '全部取消',
                    danger: true,
                );
                if (ok)
                {
                    await ref.read(downloadProvider.notifier).cancelAllActive();
                }
                break;
            case 'clear_failed':
                final ok = await _confirm(
                    title: '清除失败 / 已取消记录',
                    message: '将删除所有失败与已取消的任务记录，同时清理对应的本地部分文件。',
                    confirmText: '清除',
                    danger: true,
                );
                if (ok)
                {
                    final n = await ref.read(downloadProvider.notifier).clearFailed();
                    if (mounted) _showSnack('已清除 $n 条记录');
                }
                break;
        }
    }

    // ============================ 已下载编辑模式 ============================

    void _enterEditMode()
    {
        setState(() => _isEditMode = true);
    }

    void _exitEditMode()
    {
        setState(()
        {
            _isEditMode = false;
            _selectedAlbumIds.clear();
        });
    }

    void _toggleSelectAlbum(String albumId)
    {
        setState(()
        {
            if (_selectedAlbumIds.contains(albumId))
            {
                _selectedAlbumIds.remove(albumId);
            }
            else
            {
                _selectedAlbumIds.add(albumId);
            }
        });
    }

    void _toggleSelectAll()
    {
        final all = ref.read(libraryProvider).visibleAlbums;
        setState(()
        {
            if (_selectedAlbumIds.length == all.length)
            {
                _selectedAlbumIds.clear();
            }
            else
            {
                _selectedAlbumIds
                  ..clear()
                  ..addAll(all.map((a) => a.albumId));
            }
        });
    }

    void _invertSelection()
    {
        final all = ref.read(libraryProvider).visibleAlbums;
        setState(()
        {
            final inverted = all
                .map((a) => a.albumId)
                .where((id) => !_selectedAlbumIds.contains(id))
                .toSet();
            _selectedAlbumIds
              ..clear()
              ..addAll(inverted);
        });
    }

    /// 确认批量删除已下载
    Future<void> _confirmBatchDeleteLibrary() async
    {
        if (_selectedAlbumIds.isEmpty)
        {
            _showSnack('请先选择要删除的项');
            return;
        }
        final ok = await _confirm(
            title: '删除 ${_selectedAlbumIds.length} 本漫画',
            message: '将同时从本地删除文件，无法恢复。',
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        final (total, failed) = await ref
            .read(libraryProvider.notifier)
            .deleteAlbums(_selectedAlbumIds);
        if (!mounted) return;
        setState(() => _selectedAlbumIds.clear());
        if (failed == 0)
        {
            _showSnack('已删除 $total 本');
        }
        else
        {
            _showSnack('已删除 $total 本，$failed 本文件清理失败');
        }
    }

    /// 确认清空整个书架
    Future<void> _confirmClearAllLibrary() async
    {
        final state = ref.read(libraryProvider);
        if (state.albums.isEmpty) return;
        final ok = await _confirm(
            title: '清空所有下载',
            message: '将永久删除全部 ${state.albums.length} 本漫画及其本地文件，无法恢复。',
            confirmText: '清空',
            danger: true,
        );
        if (!ok) return;
        final failed =
            await ref.read(libraryProvider.notifier).clearAllWithFiles();
        if (!mounted) return;
        if (failed == 0)
        {
            _showSnack('已清空整个书架');
        }
        else
        {
            _showSnack('已清空，$failed 本文件清理失败');
        }
    }

    // ============================ 任务编辑模式 ============================

    void _enterTaskEditMode()
    {
        setState(() => _taskEditMode = true);
    }

    void _exitTaskEditMode()
    {
        setState(()
        {
            _taskEditMode = false;
            _selectedTaskIds.clear();
        });
    }

    void _toggleSelectTask(String taskId)
    {
        // 编辑模式下点击 tile 切换选中
        setState(()
        {
            if (_selectedTaskIds.contains(taskId))
            {
                _selectedTaskIds.remove(taskId);
            }
            else
            {
                _selectedTaskIds.add(taskId);
            }
        });
    }

    void _toggleSelectAllTasks()
    {
        final all = ref.read(downloadProvider).tasks;
        setState(()
        {
            if (_selectedTaskIds.length == all.length)
            {
                _selectedTaskIds.clear();
            }
            else
            {
                _selectedTaskIds
                  ..clear()
                  ..addAll(all.map((t) => t.taskId));
            }
        });
    }

    void _invertTaskSelection()
    {
        final all = ref.read(downloadProvider).tasks;
        setState(()
        {
            final inverted = all
                .map((t) => t.taskId)
                .where((id) => !_selectedTaskIds.contains(id))
                .toSet();
            _selectedTaskIds
              ..clear()
              ..addAll(inverted);
        });
    }

    /// 确认重试选中的任务
    Future<void> _confirmRetrySelectedTasks() async
    {
        if (_selectedTaskIds.isEmpty)
        {
            _showSnack('请先选择要重试的项');
            return;
        }
        final n = await ref
            .read(downloadProvider.notifier)
            .retryTasks(_selectedTaskIds);
        if (!mounted) return;
        setState(() => _selectedTaskIds.clear());
        _showSnack('已重试 $n 个任务');
    }

    /// 确认删除选中的任务
    Future<void> _confirmDeleteSelectedTasks() async
    {
        if (_selectedTaskIds.isEmpty)
        {
            _showSnack('请先选择要删除的项');
            return;
        }
        final ok = await _confirm(
            title: '删除 ${_selectedTaskIds.length} 个任务',
            message: '将删除这些下载任务的记录，同时清理可能存在的本地部分文件。',
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        final (total, failed) = await ref
            .read(downloadProvider.notifier)
            .deleteTasks(_selectedTaskIds);
        if (!mounted) return;
        setState(() => _selectedTaskIds.clear());
        _showSnack(failed == 0
            ? '已删除 $total 个任务'
            : '已删除 $total 个，$failed 个失败');
    }

    /// 单个任务删除
    Future<void> _confirmDeleteTask(String taskId) async
    {
        final task = ref
            .read(downloadProvider)
            .tasks
            .where((t) => t.taskId == taskId)
            .firstOrNull;
        if (task == null) return;
        final isAlbum = task.taskType == 'album';
        final message = isAlbum
            ? '将删除该任务并清理整本漫画的本地文件（已下载部分）。'
            : '将删除该任务并清理该章节的本地文件。';
        final ok = await _confirm(
            title: '删除任务',
            message: message,
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        await ref.read(downloadProvider.notifier).deleteTask(taskId);
    }

    // ============================ 通用工具 ============================

    /// 通用确认弹窗
    Future<bool> _confirm({
        required String title,
        required String message,
        String confirmText = '确定',
        String cancelText = '取消',
        bool danger = false,
    }) async
    {
        final result = await showDialog<bool>(
            context: context,
            builder: (ctx)
            {
                return AlertDialog(
                    backgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                    ),
                    title: Text(title,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    content: Text(message,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    actions: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(cancelText,
                                style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(
                                confirmText,
                                style: TextStyle(
                                    color: danger
                                        ? AppColors.error
                                        : AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                ),
                            ),
                        ),
                    ],
                );
            },
        );
        return result ?? false;
    }

    void _showSnack(String text)
    {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(text),
              backgroundColor: AppColors.surfaceVariant,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
          ));
    }

    /// 下载完成时的 SnackBar，带"查看"动作跳转到已下载 Tab
    void _showCompletionSnack(String title, int totalImages)
    {
        if (!mounted) return;
        final msg = totalImages > 0
            ? '$title 下载完成（共 $totalImages 页），已加入书架'
            : '$title 下载完成，已加入书架';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.surfaceVariant,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                  label: '查看',
                  textColor: AppColors.accent,
                  onPressed: ()
                  {
                      if (!mounted) return;
                      _tabController.animateTo(tabLibrary);
                  },
              ),
          ));
    }
}

/// 已下载分页编辑模式底栏
class _LibraryEditBar extends StatelessWidget
{
    final int count;
    final VoidCallback onDelete;

    const _LibraryEditBar({
        required this.count,
        required this.onDelete,
    });

    @override
    Widget build(BuildContext context)
    {
        return SafeArea(
            top: false,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                    ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                    children: [
                        const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                            child: Text(
                                '删除将同时清理本地文件',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                ),
                            ),
                        ),
                        FilledButton.icon(
                            onPressed: count == 0 ? null : onDelete,
                            icon: const Icon(Icons.delete, size: 18),
                            label: Text('删除 ($count)'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.error,
                                disabledBackgroundColor:
                                    AppColors.error.withValues(alpha: 0.3),
                                foregroundColor: Colors.white,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}

/// 下载中分页编辑模式底栏
class _TaskEditBar extends StatelessWidget
{
    final int count;
    final VoidCallback onRetry;
    final VoidCallback onDelete;

    const _TaskEditBar({
        required this.count,
        required this.onRetry,
        required this.onDelete,
    });

    @override
    Widget build(BuildContext context)
    {
        return SafeArea(
            top: false,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                    ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                    children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: count == 0 ? null : onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text('重试 ($count)'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                    side: BorderSide(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.5),
                                    ),
                                ),
                            ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: FilledButton.icon(
                                onPressed: count == 0 ? null : onDelete,
                                icon: const Icon(Icons.delete, size: 18),
                                label: Text('删除 ($count)'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    disabledBackgroundColor:
                                        AppColors.error.withValues(alpha: 0.3),
                                    foregroundColor: Colors.white,
                                ),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}
