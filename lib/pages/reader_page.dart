import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/reader_provider.dart';
import '../core/jm/jm_image.dart';
import '../theme/app_colors.dart';

/// 阅读器页
class ReaderPage extends ConsumerStatefulWidget {
  /// 章节 ID
  final String photoId;

  const ReaderPage({
    super.key,
    required this.photoId,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(readerProvider(widget.photoId).notifier).loadPages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider(widget.photoId));

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () =>
            ref.read(readerProvider(widget.photoId).notifier).toggleControls(),
        child: Stack(
          children: [
            // 图片内容
            _buildContent(state),
            // 控制栏
            if (state.showControls) _buildControls(state),
          ],
        ),
      ),
    );
  }

  /// 构建图片内容
  Widget _buildContent(ReaderState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (state.error != null) {
      return Center(
        child: Text(
          state.error!,
          style: const TextStyle(color: AppColors.error),
        ),
      );
    }

    if (state.imageUrls.isEmpty) {
      return const Center(
        child: Text(
          '暂无图片',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return _buildVerticalScroll(state);
  }

  /// 纵向滚动模式
  Widget _buildVerticalScroll(ReaderState state) {
    return ListView.builder(
      itemCount: state.imageUrls.length,
      itemBuilder: (context, index) {
        return _buildImageItem(state.imageUrls[index], index);
      },
    );
  }

  /// 构建单张图片（按原比例完整显示，撑满设备宽度）
  /// 关键：用 LayoutBuilder 拿到父容器实际宽度，强制 CachedNetworkImage.width = 父容器宽度
  /// 这样图片按宽度比例缩放、完整显示，layout 高度 = 显示高度（无空白）
  Widget _buildImageItem(String url, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CachedNetworkImage(
          imageUrl: url,
          cacheManager: JmImageCacheManager.instance,
          width: constraints.maxWidth,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(
            color: AppColors.surface,
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: AppColors.surface,
            child: const Center(
              child: Icon(Icons.broken_image, color: AppColors.textDisabled),
            ),
          ),
        );
      },
    );
  }

  /// 构建控制栏
  Widget _buildControls(ReaderState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 顶部控制栏
        Container(
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
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  '${state.currentPage + 1} / ${state.totalPages}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        // 底部控制栏
        Container(
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: state.currentPage > 0
                    ? () => ref
                        .read(readerProvider(widget.photoId).notifier)
                        .prevPage()
                    : null,
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: state.currentPage < state.totalPages - 1
                    ? () => ref
                        .read(readerProvider(widget.photoId).notifier)
                        .nextPage()
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
