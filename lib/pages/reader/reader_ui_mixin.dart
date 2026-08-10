import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../widgets/chapter_catalog_drawer.dart';
import 'reader_base_mixin.dart';
import 'reader_gesture_mixin.dart';

/// 阅读器 UI 构建 mixin
///
/// 封装页面布局、控制栏、进度条、章节切换遮罩等 UI 构建逻辑。
/// 依赖 [ReaderBaseMixin] 提供阅读器状态与操作回调。
mixin ReaderUIMixin<T extends ConsumerStatefulWidget>
    on ReaderBaseMixin<T>, ReaderGestureMixin<T> {
  // ==================== 页面布局 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        autofocus: true,
        child: Listener(
          onPointerDown: onPointerDown,
          onPointerMove: onPointerMove,
          onPointerUp: onPointerUp,
          onPointerCancel: onPointerCancel,
          child: GestureDetector(
            onTap: onTap,
            onHorizontalDragStart: onHorizontalDragStart,
            onHorizontalDragUpdate: onHorizontalDragUpdate,
            onHorizontalDragEnd: onHorizontalDragEnd,
            child: Stack(
              children: [
                buildContent(),
                if (chapterLoading)
                  Positioned.fill(child: _buildChapterLoadingOverlay()),
                if (showControls &&
                    !isLoading &&
                    !chapterLoading &&
                    error == null)
                  Positioned.fill(child: _buildControls(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 控制栏与遮罩 ====================

  /// 构建控制栏框架
  ///
  /// 【性能优化】
  /// 顶部栏使用 episodeName（章节切换才变化），底层 Column 不依赖 currentPage
  /// 底部栏内部使用 [ValueListenableBuilder] 监听 [currentPageNotifier]，
  /// 页码变化时只重建底部栏局部，不触发整个 reader 重建
  Widget _buildControls(BuildContext context) {
    final total = totalPages;
    final episodeName = currentChapterName;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTopBar(context, episodeName),
        _buildBottomBar(context, total),
      ],
    );
  }

  /// 构建章节切换加载遮罩
  Widget _buildChapterLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: context.appColors.accent,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              '正在切换章节...',
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

  /// 构建顶部控制栏
  ///
  /// 【性能优化】
  /// 顶部页码显示使用 [ValueListenableBuilder] 监听 [currentPageNotifier]，
  /// 页码变化时只重建 Text 局部，不触发整个 reader 重建
  Widget _buildTopBar(BuildContext context, String episodeName) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              children: [
                if (episodeName.isNotEmpty)
                  Text(
                    episodeName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ValueListenableBuilder<int>(
                  valueListenable: currentPageNotifier,
                  builder: (context, page, _) {
                    return Text(
                      '${page + 1} / $totalPages',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // 目录按钮
          IconButton(
            icon: const Icon(Icons.list, color: Colors.white),
            onPressed: showCatalog,
            tooltip: '目录',
          ),
        ],
      ),
    );
  }

  /// 构建底部控制栏
  ///
  /// 【性能优化】
  /// 进度条 + 翻页按钮使用 [ValueListenableBuilder] 监听 [currentPageNotifier]，
  /// 页码变化时只重建底部栏内部局部，不触发整个 reader 重建
  Widget _buildBottomBar(BuildContext context, int total) {
    // 章节导航是否可用
    final canNavigate =
        albumDetail != null && albumDetail!.episodes.length > 1;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          if (total > 0)
            ValueListenableBuilder<int>(
              valueListenable: currentPageNotifier,
              builder: (context, page, _) => _buildProgressBar(total, page),
            ),
          const SizedBox(height: 8),
          // 章节导航提示（无法切换时）
          if (!canNavigate)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: albumDetail == null
                  ? GestureDetector(
                      onTap: retryLoadAlbumDetail,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            color: context.appColors.accent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '章节信息获取失败，点击重试',
                            style: TextStyle(
                              color: context.appColors.accent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Text(
                      '仅单章',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
            ),
          // 按钮行
          ValueListenableBuilder<int>(
            valueListenable: currentPageNotifier,
            builder: (context, page, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 上一章
                  IconButton(
                    icon: Icon(
                      Icons.skip_previous,
                      color: hasPrevChapter ? Colors.white : Colors.white24,
                    ),
                    onPressed: hasPrevChapter ? goToPrevChapter : null,
                    tooltip: '上一章',
                  ),
                  const SizedBox(width: 16),
                  // 上一页
                  IconButton(
                    icon: const Icon(
                      Icons.navigate_before,
                      color: Colors.white,
                    ),
                    onPressed: page > 0 ? () => setPage(page - 1) : null,
                    tooltip: '上一页',
                  ),
                  const SizedBox(width: 16),
                  // 下一页
                  IconButton(
                    icon: const Icon(
                      Icons.navigate_next,
                      color: Colors.white,
                    ),
                    onPressed: page < total - 1
                        ? () => setPage(page + 1)
                        : null,
                    tooltip: '下一页',
                  ),
                  const SizedBox(width: 16),
                  // 下一章
                  IconButton(
                    icon: Icon(
                      Icons.skip_next,
                      color: hasNextChapter ? Colors.white : Colors.white24,
                    ),
                    onPressed: hasNextChapter ? goToNextChapter : null,
                    tooltip: '下一章',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 构建进度条
  ///
  /// 【性能优化】
  /// - [Slider.onChanged]：拖动中仅用 [scrollToPage] 的 instant 模式
  ///   （[ScrollController.jumpTo]）无动画滚动，不调用 setState，
  ///   滚动事件触发 [ReaderBaseMixin._onScroll] 自动同步 [currentPageNotifier]
  /// - [Slider.onChangeEnd]：拖动结束时持久化进度（一次写库）
  ///   避免拖动过程中每帧写 SQLite 导致的卡顿
  Widget _buildProgressBar(int total, int page) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            '${page + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: context.appColors.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: context.appColors.accent,
              overlayColor: context.appColors.accent.withValues(alpha: 0.12),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 7,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 16,
              ),
            ),
            child: Slider(
              value: total > 1 ? page / (total - 1) : 0.0,
              onChanged: total > 1
                  ? (value) {
                      final target =
                          (value * (total - 1)).round().clamp(0, total - 1);
                      // 拖动中：仅 jumpTo 滚动，不写库、不 setState
                      // _onScroll 会同步 currentPageNotifier，UI 自动更新
                      scrollToPage(target, instant: true);
                    }
                  : null,
              onChangeEnd: (value) {
                final target =
                    (value * (total - 1)).round().clamp(0, total - 1);
                // 拖动结束：同步状态 + 立即持久化进度
                setCurrentPage(target);
                persistProgress();
              },
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$total',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  /// 显示章节目录
  void showCatalog() {
    if (albumDetail == null || albumDetail!.episodes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ChapterCatalogDrawer(
          episodes: albumDetail!.episodes,
          currentPhotoId: activePhotoId,
          onChapterSelected: (episode) {
            loadChapter(episode.photoId);
          },
        );
      },
    );
  }

  /// 跳转到指定页并滚动
  ///
  /// 【性能优化】
  /// 用于翻页按钮，使用动画滚动（[scrollToPage] 默认 animateTo）
  void setPage(int page) {
    if (page < 0 || page >= totalPages) return;
    setCurrentPage(page);
    scrollToPage(page);
  }
}
