import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/library_album_model.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/downloaded_album_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/sort_filter_bar.dart';
import '../widgets/storage_summary_bar.dart';
import 'download_page.dart';

/// 已下载分页状态与 UI 封装
mixin DownloadPageLibraryMixin on ConsumerState<DownloadPage>
{
    /// 是否处于编辑模式
    bool get isLibraryEditMode;

    /// 设置编辑模式
    set isLibraryEditMode(bool value);

    /// 当前选中的 albumId
    Set<String> get selectedAlbumIds;

    /// 延迟刷新缺失封面的已调度 albumId
    Set<String> get coverRefreshScheduled;

    /// 打开下载根目录回调
    Future<void> openDownloadDirectory();

    /// 显示 SnackBar 回调
    void showSnack(String text);

    /// 通用确认弹窗回调
    Future<bool> confirm({
        required String title,
        required String message,
        String confirmText,
        bool danger,
    });

    /// 构建已下载分页主体
    Widget buildLibraryTab()
    {
        final state = ref.watch(libraryProvider);
        final visible = state.visibleAlbums;

        return Column(
            children: [
                StorageSummaryBar(
                    albumCount: state.albums.length,
                    episodeCount: state.totalDownloadedEpisodes,
                    totalBytes: state.totalSizeBytes,
                    fileCount: state.totalFileCount,
                    isLoading: state.isLoading,
                    onMoreTap: openDownloadDirectory,
                ),
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
                    isEditing: isLibraryEditMode,
                    onEnterEditMode: state.albums.isEmpty
                        ? null
                        : () => setState(() => isLibraryEditMode = true),
                ),
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
            _scheduleLazyCoverRefresh(visible);
            return _buildEmptyLibrary();
        }
        if (visible.isEmpty)
        {
            return _buildNoMatch();
        }
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
                    isEditing: isLibraryEditMode,
                    isSelected: selectedAlbumIds.contains(album.albumId),
                    onTap: ()
                    {
                        if (isLibraryEditMode)
                        {
                            _toggleSelectAlbum(album.albumId);
                        }
                        else
                        {
                            _openAlbumDetail(album);
                        }
                    },
                    onLongPress: ()
                    {
                        if (!isLibraryEditMode)
                        {
                            setState(() => isLibraryEditMode = true);
                        }
                        _toggleSelectAlbum(album.albumId);
                    },
                );
            },
        );
    }

    /// 延迟刷新缺失封面
    void _scheduleLazyCoverRefresh(List<LibraryAlbumModel> visible)
    {
        final pending = visible
            .where((a) =>
                a.coverPath.isEmpty || !File(a.coverPath).existsSync())
            .where((a) => !coverRefreshScheduled.contains(a.albumId))
            .toList();
        if (pending.isEmpty) return;
        for (final album in pending)
        {
            coverRefreshScheduled.add(album.albumId);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) async
        {
            if (!mounted) return;
            for (final album in pending)
            {
                ref.read(libraryProvider.notifier).refreshCover(album);
            }
        });
    }

    /// 空状态
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
                            color: context.appColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '书架空空如也',
                            style: TextStyle(
                                color: context.appColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                            ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            '去搜索感兴趣的漫画并下载吧',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
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
                            color: context.appColors.textDisabled.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 12),
                        Text(
                            '没有匹配的本子',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 跳转到本子详情页（与主页一致）
    /// 由详情页统一展示章节列表，让用户自主选择阅读或下载某一章节
    void _openAlbumDetail(LibraryAlbumModel album)
    {
        context.push('/album/${album.albumId}');
    }

    /// 切换单本选中
    void _toggleSelectAlbum(String albumId)
    {
        setState(()
        {
            if (selectedAlbumIds.contains(albumId))
            {
                selectedAlbumIds.remove(albumId);
            }
            else
            {
                selectedAlbumIds.add(albumId);
            }
        });
    }

    /// 全选/取消全选
    void toggleSelectAllLibrary()
    {
        final all = ref.read(libraryProvider).visibleAlbums;
        setState(()
        {
            if (selectedAlbumIds.length == all.length)
            {
                selectedAlbumIds.clear();
            }
            else
            {
                selectedAlbumIds
                  ..clear()
                  ..addAll(all.map((a) => a.albumId));
            }
        });
    }

    /// 反选
    void invertLibrarySelection()
    {
        final all = ref.read(libraryProvider).visibleAlbums;
        setState(()
        {
            final inverted = all
                .map((a) => a.albumId)
                .where((id) => !selectedAlbumIds.contains(id))
                .toSet();
            selectedAlbumIds
              ..clear()
              ..addAll(inverted);
        });
    }

    /// 确认批量删除已下载
    Future<void> confirmBatchDeleteLibrary() async
    {
        if (selectedAlbumIds.isEmpty)
        {
            showSnack('请先选择要删除的项');
            return;
        }
        final ok = await confirm(
            title: '删除 ${selectedAlbumIds.length} 本漫画',
            message: '将同时从本地删除文件，无法恢复。',
            confirmText: '删除',
            danger: true,
        );
        if (!ok) return;
        final (total, failed) = await ref
            .read(libraryProvider.notifier)
            .deleteAlbums(selectedAlbumIds);
        if (!mounted) return;
        setState(() => selectedAlbumIds.clear());
        if (failed == 0)
        {
            showSnack('已删除 $total 本');
        }
        else
        {
            showSnack('已删除 $total 本，$failed 本文件清理失败');
        }
    }

    /// 确认清空整个书架
    Future<void> confirmClearAllLibrary() async
    {
        final state = ref.read(libraryProvider);
        if (state.albums.isEmpty) return;
        final ok = await confirm(
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
            showSnack('已清空整个书架');
        }
        else
        {
            showSnack('已清空，$failed 本文件清理失败');
        }
    }

    /// 已下载分页菜单回调
    void handleLibraryMenu(String value) async
    {
        switch (value)
        {
            case 'open_dir':
                await openDownloadDirectory();
                break;
            case 'refresh':
                await ref.read(libraryProvider.notifier).refreshAllSizeStats();
                if (mounted)
                {
                    showSnack('已刷新占用统计');
                }
                break;
            case 'orphan':
                final removed =
                    await ref.read(libraryProvider.notifier).cleanupOrphanFolders();
                if (!mounted) return;
                showSnack(removed == 0 ? '没有发现孤儿文件夹' : '已清理 $removed 个文件夹');
                break;
            case 'clear':
                await confirmClearAllLibrary();
                break;
        }
    }
}
