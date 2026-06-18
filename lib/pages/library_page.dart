import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/library_provider.dart';
import '../data/models/library_album_model.dart';
import '../theme/app_colors.dart';
import '../widgets/loading_widget.dart';

/// 书架页
class LibraryPage extends ConsumerStatefulWidget
{
    const LibraryPage({super.key});

    @override
    ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
{
    bool _isEditMode = false;
    final Set<String> _selectedIds = {};

    @override
    void initState()
    {
        super.initState();
        Future.microtask(() => ref.read(libraryProvider.notifier).loadLibrary());
    }

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(libraryProvider);

        return Scaffold(
            appBar: AppBar(
                title: const Text('书架'),
                actions: [
                    IconButton(
                        icon: Icon(_isEditMode ? Icons.check : Icons.edit),
                        onPressed: () => setState(() => _isEditMode = !_isEditMode),
                    ),
                    IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshLibrary,
                    ),
                ],
            ),
            body: _buildBody(state),
        );
    }

    /// 构建主体
    Widget _buildBody(LibraryState state)
    {
        if (state.isLoading && state.albums.isEmpty)
        {
            return const LoadingWidget(message: '加载书架中...');
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
                            color: context.appColors.textDisabled.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '书架为空',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 16,
                            ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            '下载漫画后会自动添加到书架',
                            style: TextStyle(
                                color: context.appColors.textDisabled,
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
                final album = state.albums[index];
                return _buildAlbumCard(album);
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
                    // 打开阅读器或详情
                    context.push('/album/${album.albumId}');
                }
            },
            child: Stack(
                children: [
                    Container(
                        decoration: BoxDecoration(
                            color: context.appColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: context.appColors.accent, width: 2)
                                : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(
                                    child: Container(
                                        color: context.appColors.surfaceVariant,
                                        child: Center(
                                            child: album.coverPath.isNotEmpty
                                                ? Image.file(
                                                    File(album.coverPath),
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    errorBuilder: (_, __, ___) =>
                                                        Icon(
                                                            Icons.broken_image,
                                                            color: context.appColors.textDisabled,
                                                        ),
                                                )
                                                : Icon(
                                                    Icons.image_outlined,
                                                    color: context.appColors.textDisabled,
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
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: context.appColors.textPrimary,
                                                ),
                                            ),
                                            if (album.lastReadPage > 0)
                                                Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Text(
                                                        '读到第 ${album.lastReadPage} 页',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: context.appColors.accent,
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
                                        ? context.appColors.accent
                                        : context.appColors.surfaceVariant,
                                ),
                                child: isSelected
                                    ? Icon(Icons.check, size: 16, color: context.appColors.background)
                                    : null,
                            ),
                        ),
                ],
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
        // 使用默认下载目录刷新
        await ref.read(libraryProvider.notifier).refreshLibrary('');
    }
}
