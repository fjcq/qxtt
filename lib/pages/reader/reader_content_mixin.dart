import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../widgets/waiting_page_placeholder.dart';
import 'chapter_page_item.dart';
import 'reader_chapter_mixin.dart';

/// 离线阅读器内容构建 mixin
///
/// 负责构建加载中、错误、空数据以及图片列表等阅读内容。
/// 依赖 [ReaderChapterMixin] 提供本地图片路径与加载状态。
///
/// 【统一阅读架构】
/// 阅读器只读本地文件，未下载页通过 [WaitingPagePlaceholder] 显示占位与进度。
/// 父级 [ReaderChapterMixin] 订阅 [DownloadService.onProgress]，
/// 单页完成后会刷新对应 [ChapterPageItem] 的本地路径，
/// 占位组件随之被 [Image.file] 替换，无需自身监听下载事件。
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
    ///
    /// 【性能优化】
    /// - [addAutomaticKeepAlives]：保留可见项外的几个相邻页的 State，避免来回滚动重复解码
    /// - [addRepaintBoundaries]：默认为 true，为每个 item 包 RepaintBoundary，
    ///   setState 触发重建时不会让所有图片重新绘制，只有变化的页才会重绘
    Widget _buildVerticalScroll() {
        return ListView.builder(
            controller: scrollController,
            itemCount: chapterPages.length,
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
            scrollCacheExtent: ScrollCacheExtent.pixels(isDesktop ? 800 : 400),
            itemBuilder: (context, index) {
                return _buildPageItem(chapterPages[index]);
            },
        );
    }

    /// 渲染单个章节页（统一阅读架构：本地优先，未下载页占位）
    ///
    /// 【性能优化】
    /// 用 [RepaintBoundary] 包裹每个页项，配合 [ListView.addRepaintBoundaries]
    /// 形成独立绘制层。父级 setState 时各页独立合成，避免相邻图片被一起重绘
    Widget _buildPageItem(ChapterPageItem item) {
        return RepaintBoundary(
            child: item.hasLocal
                ? _buildLocalImage(item.localPath!)
                : (item.needNetwork
                    ? _buildWaitingPlaceholder(item)
                    : _buildMissingPlaceholder(item)),
        );
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

    /// 未下载页占位组件
    ///
    /// 【统一阅读架构】
    /// 章节本地未就绪时显示 [WaitingPagePlaceholder]，传入章节整体进度。
    /// 父级订阅下载事件后会刷新对应 [ChapterPageItem] 的本地路径，
    /// 该页随之从占位切换为 [Image.file]，无需自身监听流。
    Widget _buildWaitingPlaceholder(ChapterPageItem item) {
        return WaitingPagePlaceholder(
            key: ValueKey('${activePhotoId}_${item.index}_waiting'),
            pageIndex: item.index,
            progress: chapterDownloadCompleted
                ? 1.0
                : (chapterDownloadTotal > 0 ? chapterDownloadProgress : null),
            current: chapterDownloadCurrent,
            total: chapterDownloadTotal,
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
