import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reader/reader_download_engine.dart';
import '../../providers/config_provider.dart';
import '../../providers/reader_providers.dart';
import '../../theme/app_colors.dart';
import '../../widgets/online_image_viewer.dart';
import 'chapter_page_item.dart';
import 'reader_chapter_mixin.dart';

/// 离线阅读器内容构建 mixin
///
/// 负责构建加载中、错误、空数据以及图片列表等阅读内容。
/// 依赖 [ReaderChapterMixin] 提供本地图片路径与加载状态。
///
/// 【边下边看】
/// 通过 [_buildPageItem] 渲染 [ChapterPageItem]：
/// - [ChapterPageItem.hasLocal] 为 true → 直接 Image.file
/// - [ChapterPageItem.needNetwork] 为 true → 走 OnlineImageViewer（与在线阅读一致）
/// 缺失页下载到本地后会自动通过 .ok 标记识别为本地，刷新后展示本地图。
mixin ReaderContentMixin<T extends ConsumerStatefulWidget>
    on ReaderChapterMixin<T> {
    @override
    Widget buildContent() => _buildContent();

    @override
    Widget buildImageForIndex(int index) {
        if (index < 0 || index >= chapterPages.length) {
            return const SizedBox.shrink();
        }
        return _buildPageItem(chapterPages[index]);
    }

    /// 构建图片内容主体
    Widget _buildContent() {
        if (isLoading) {
            return Center(
                child:
                    CircularProgressIndicator(color: context.appColors.accent),
            );
        }

        if (error != null) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Icon(
                                Icons.error_outline,
                                color: context.appColors.error,
                                size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                                error!,
                                style: TextStyle(
                                    color: context.appColors.textSecondary,
                                    fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: () {
                                    loadChapter(activePhotoId);
                                },
                                child: const Text('重试'),
                            ),
                        ],
                    ),
                ),
            );
        }

        if (chapterPages.isEmpty) {
            return Center(
                child: Text(
                    '暂无图片',
                    style: TextStyle(color: context.appColors.textSecondary),
                ),
            );
        }

        return _buildVerticalScroll();
    }

    /// 纵向滚动模式
    Widget _buildVerticalScroll() {
        return ListView.builder(
            controller: scrollController,
            itemCount: chapterPages.length,
            scrollCacheExtent: ScrollCacheExtent.pixels(isDesktop ? 800 : 400),
            itemBuilder: (context, index) {
                return _buildPageItem(chapterPages[index]);
            },
        );
    }

    /// 渲染单个章节页（混合渲染核心）
    Widget _buildPageItem(ChapterPageItem item) {
        if (item.hasLocal) {
            return _buildLocalImage(item.localPath!);
        }
        if (item.needNetwork) {
            return _buildNetworkImage(item);
        }
        return _buildMissingPlaceholder(item);
    }

    /// 本地图片渲染
    ///
    /// 【性能优化】
    /// - 移动端：cacheWidth = displayWidth * 2，避免大图占满内存
    /// - 桌面端：cacheWidth 上限 3840（4K），平衡高清显示与内存压力
    Widget _buildLocalImage(String path) {
        return LayoutBuilder(
            builder: (context, constraints) {
                final displayWidth = constraints.maxWidth * globalScale;
                final cacheWidth = _resolveCacheWidth(displayWidth);
                return ColoredBox(
                    color: Colors.black,
                    child: Image.file(
                        File(path),
                        width: displayWidth,
                        fit: BoxFit.contain,
                        cacheWidth: cacheWidth,
                        errorBuilder: (context, error, stackTrace) {
                            return Container(
                                color: context.appColors.surface,
                                child: Center(
                                    child: Icon(
                                        Icons.broken_image,
                                        color: context.appColors.textDisabled,
                                    ),
                                ),
                            );
                        },
                    ),
                );
            },
        );
    }

    /// 根据平台与显示宽度计算图片解码缓存宽度
    /// 返回 null 表示让框架按原始尺寸解码（仅用于极少数需要原片的场景）
    int? _resolveCacheWidth(double displayWidth) {
        if (isDesktop) {
            // 桌面端：上限 4K，避免超大图导致内存压力
            const desktopMaxCacheWidth = 3840;
            final target = (displayWidth * 2).toInt();
            return target < desktopMaxCacheWidth
                ? target
                : desktopMaxCacheWidth;
        }
        // 移动端：按显示宽度 2 倍解码，节省内存
        return (displayWidth * 2).toInt();
    }

    /// 网络图片渲染（与在线阅读一致）
    Widget _buildNetworkImage(ChapterPageItem item) {
        final loader = ref.read(readerImageLoaderProvider);
        final config = ref.read(configProvider).config;
        final distance = (item.index - currentPage).abs();
        final priority = distance == 0
            ? DownloadPriority.immediate
            : distance <= config.preloadPageCount
                ? DownloadPriority.preload
                : DownloadPriority.background;

        return OnlineImageViewer(
            key: ValueKey('${activePhotoId}_${item.index}'),
            photoId: activePhotoId,
            filename: item.filename!,
            scrambleId: item.scrambleId,
            aid: item.aid,
            loader: loader,
            localFilePath: null,
            priority: priority,
            scale: globalScale,
        );
    }

    /// 缺失占位（既无本地也无网络信息时）
    Widget _buildMissingPlaceholder(ChapterPageItem item) {
        return Container(
            color: Colors.black,
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.image_not_supported_outlined,
                            color: context.appColors.textDisabled,
                            size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                            '第 ${item.index + 1} 页 暂不可用',
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 12,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}
