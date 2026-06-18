import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/config_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import '../utils/directory_opener.dart';
import '../utils/library_storage.dart';
import 'download_page_dialogs.dart';
import 'download_page_download_mixin.dart';
import 'download_page_edit_bars.dart';
import 'download_page_library_mixin.dart';

/// 下载页（含已下载/下载中两个分页）
/// 重构点：
/// - 顶部展示存储信息
/// - 已下载分页支持排序、搜索、编辑模式、批量删除
/// - 下载中分页按状态分组（active/failed），支持单条与批量操作
class DownloadPage extends ConsumerStatefulWidget
{
    const DownloadPage({super.key});

    @override
    ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with
        TickerProviderStateMixin,
        DownloadPageLibraryMixin,
        DownloadPageDownloadMixin
{
    /// 当前 Tab 索引
    static const int tabLibrary = 0;
    static const int tabDownload = 1;

    late final TabController _tabController;

    @override
    bool isLibraryEditMode = false;

    @override
    final Set<String> selectedAlbumIds = {};

    @override
    final Set<String> coverRefreshScheduled = {};

    @override
    bool isTaskEditMode = false;

    @override
    final Set<String> selectedTaskIds = {};

    @override
    void initState()
    {
        super.initState();
        _tabController = TabController(length: 2, vsync: this);
        _tabController.addListener(_onTabChanged);
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
        if (isLibraryEditMode || isTaskEditMode)
        {
            setState(()
            {
                isLibraryEditMode = false;
                isTaskEditMode = false;
                selectedAlbumIds.clear();
                selectedTaskIds.clear();
            });
        }
        else
        {
            setState(() {});
        }
        if (_tabController.index == tabLibrary)
        {
            Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
        }
    }

    @override
    Widget build(BuildContext context)
    {
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
                    buildLibraryTab(),
                    buildDownloadTab(),
                ],
            ),
            bottomNavigationBar: _buildBottomBar(),
        );
    }

    /// 顶部导航栏
    PreferredSizeWidget _buildAppBar()
    {
        final showLibraryActions = _tabController.index == tabLibrary;
        final showDownloadActions = _tabController.index == tabDownload;
        return AppBar(
            title: Text(isLibraryEditMode
                ? '已选择 ${selectedAlbumIds.length} 项'
                : (isTaskEditMode
                    ? '已选择 ${selectedTaskIds.length} 项'
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
        if (isLibraryEditMode)
        {
            return [
                IconButton(
                    tooltip: '全选',
                    icon: const Icon(Icons.select_all),
                    onPressed: toggleSelectAllLibrary,
                ),
                IconButton(
                    tooltip: '反选',
                    icon: const Icon(Icons.flip),
                    onPressed: invertLibrarySelection,
                ),
                IconButton(
                    tooltip: '退出编辑',
                    icon: const Icon(Icons.close),
                    onPressed: _exitLibraryEditMode,
                ),
            ];
        }
        return [
            IconButton(
                tooltip: '管理',
                icon: const Icon(Icons.checklist_rtl),
                onPressed: () => setState(() => isLibraryEditMode = true),
            ),
            PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) async
                {
                    if (v == 'open_dir')
                    {
                        await openDownloadDirectory();
                    }
                    else
                    {
                        handleLibraryMenu(v);
                    }
                },
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
        if (isTaskEditMode)
        {
            return [
                IconButton(
                    tooltip: '全选',
                    icon: const Icon(Icons.select_all),
                    onPressed: toggleSelectAllTasks,
                ),
                IconButton(
                    tooltip: '反选',
                    icon: const Icon(Icons.flip),
                    onPressed: invertTaskSelection,
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
                onPressed: () => setState(() => isTaskEditMode = true),
            ),
            PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) async
                {
                    if (v == 'open_dir')
                    {
                        await openDownloadDirectory();
                    }
                    else
                    {
                        handleDownloadMenu(v);
                    }
                },
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
        if (_tabController.index == tabLibrary && isLibraryEditMode)
        {
            return LibraryEditBar(
                count: selectedAlbumIds.length,
                onDelete: confirmBatchDeleteLibrary,
            );
        }
        if (_tabController.index == tabDownload && isTaskEditMode)
        {
            return TaskEditBar(
                count: selectedTaskIds.length,
                onRetry: confirmRetrySelectedTasks,
                onDelete: confirmDeleteSelectedTasks,
            );
        }
        return null;
    }

    void _exitLibraryEditMode()
    {
        setState(()
        {
            isLibraryEditMode = false;
            selectedAlbumIds.clear();
        });
    }

    void _exitTaskEditMode()
    {
        setState(()
        {
            isTaskEditMode = false;
            selectedTaskIds.clear();
        });
    }

    /// 在系统文件管理器中打开下载根目录
    @override
    Future<void> openDownloadDirectory() async
    {
        try
        {
            final configured = ref.read(configProvider).config.downloadDir;
            final dir = await LibraryStorage.getDownloadDir(
                configured: configured,
            );
            final opened = await DirectoryOpener.open(dir);
            if (!mounted) return;
            if (!opened)
            {
                showSnack('无法打开目录：$dir');
            }
        }
        catch (e)
        {
            if (!mounted) return;
            showSnack('打开目录失败：$e');
        }
    }

    /// 通用确认弹窗
    @override
    Future<bool> confirm({
        required String title,
        required String message,
        String confirmText = '确定',
        bool danger = false,
    }) async
    {
        return showConfirmDialog(
            context: context,
            title: title,
            message: message,
            confirmText: confirmText,
            danger: danger,
        );
    }

    /// 显示普通 SnackBar
    @override
    void showSnack(String text)
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
