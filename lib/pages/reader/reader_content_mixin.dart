import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import 'reader_chapter_mixin.dart';

/// 离线阅读器内容构建 mixin
///
/// 负责构建加载中、错误、空数据以及图片列表等阅读内容。
/// 依赖 [ReaderChapterMixin] 提供本地图片路径与加载状态。
mixin ReaderContentMixin<T extends ConsumerStatefulWidget> on ReaderChapterMixin<T>
{
    @override
    Widget buildContent() => _buildContent();

    @override
    Widget buildImageForIndex(int index) => _buildImageItem(imagePaths[index]);

    /// 构建图片内容主体
    Widget _buildContent()
    {
        if (isLoading)
        {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
            );
        }

        if (error != null)
        {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                                error!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: ()
                                {
                                    loadChapter(activePhotoId);
                                },
                                child: const Text('重试'),
                            ),
                        ],
                    ),
                ),
            );
        }

        if (imagePaths.isEmpty)
        {
            return const Center(
                child: Text(
                    '暂无图片',
                    style: TextStyle(color: AppColors.textSecondary),
                ),
            );
        }

        return _buildVerticalScroll();
    }

    /// 纵向滚动模式
    Widget _buildVerticalScroll()
    {
        return ListView.builder(
            controller: scrollController,
            itemCount: imagePaths.length,
            scrollCacheExtent: ScrollCacheExtent.pixels(isDesktop ? 800 : 400),
            itemBuilder: (context, index)
            {
                return buildImageForIndex(index);
            },
        );
    }

    /// 构建单张图片（全局缩放通过调整图片宽度实现）
    Widget _buildImageItem(String path)
    {
        return LayoutBuilder(
            builder: (context, constraints)
            {
                final displayWidth = constraints.maxWidth * globalScale;
                return ColoredBox(
                    color: Colors.black,
                    child: Image.file(
                        File(path),
                        width: displayWidth,
                        fit: BoxFit.contain,
                        cacheWidth: isDesktop ? null : (displayWidth * 2).toInt(),
                        errorBuilder: (context, error, stackTrace)
                        {
                            return Container(
                                color: AppColors.surface,
                                child: const Center(
                                    child: Icon(
                                        Icons.broken_image,
                                        color: AppColors.textDisabled,
                                    ),
                                ),
                            );
                        },
                    ),
                );
            },
        );
    }
}
