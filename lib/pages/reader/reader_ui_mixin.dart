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
                Text(
                  '${currentPage + 1} / $totalPages',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
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
          if (total > 0) _buildProgressBar(total),
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
          Row(
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
                onPressed: currentPage > 0
                    ? () => setPage(currentPage - 1)
                    : null,
                tooltip: '上一页',
              ),
              const SizedBox(width: 16),
              // 下一页
              IconButton(
                icon: const Icon(
                  Icons.navigate_next,
                  color: Colors.white,
                ),
                onPressed: currentPage < total - 1
                    ? () => setPage(currentPage + 1)
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
          ),
        ],
      ),
    );
  }

  /// 构建进度条
  Widget _buildProgressBar(int total) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            '${currentPage + 1}',
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
              value: total > 1 ? currentPage / (total - 1) : 0.0,
              onChanged: (value) {
                final page = (value * (total - 1)).round();
                setPage(page);
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
  void setPage(int page) {
    if (page < 0 || page >= totalPages) return;
    setCurrentPage(page);
    scrollToPage(page);
  }
}
