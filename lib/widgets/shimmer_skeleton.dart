import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// 骨架占位色块
///
/// 颜色仅作为 ShaderMask 的遮罩依据，实际显示颜色由 [Shimmer] 统一着色。
class _SkeletonBox extends StatelessWidget
{
    /// 色块宽度（null 表示撑满可用宽度）
    final double? width;

    /// 色块高度
    final double height;

    /// 圆角
    final BorderRadius borderRadius;

    const _SkeletonBox({
        required this.height,
        this.width,
        this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    });

    @override
    Widget build(BuildContext context)
    {
        return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: borderRadius,
            ),
        );
    }
}

/// 单个本子卡片骨架
///
/// 结构对齐 [AlbumCard]：上封面区 + 底部两行标题条 + 一行作者条。
class AlbumCardSkeleton extends StatelessWidget
{
    const AlbumCardSkeleton({super.key});

    @override
    Widget build(BuildContext context)
    {
        return Container(
            decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                    BoxShadow(
                        color: context.appColors.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                    ),
                ],
            ),
            clipBehavior: Clip.antiAlias,
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // 封面占位
                    Expanded(child: _SkeletonBox(height: double.infinity, borderRadius: BorderRadius.zero)),
                    // 标题与作者占位
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                _SkeletonBox(height: 11),
                                SizedBox(height: 4),
                                _SkeletonBox(height: 11, width: 72),
                                SizedBox(height: 6),
                                _SkeletonBox(height: 9, width: 48),
                            ],
                        ),
                    ),
                ],
            ),
        );
    }
}

/// 本子网格骨架屏
///
/// 用于首页 / 分类 / 搜索等列表页的首屏加载态：
/// 3 列网格 + shimmer 微光动画，结构与 AlbumCard 网格完全一致，
/// 加载完成后骨架 → 真实卡片的位置几乎不变，观感更平滑。
class AlbumGridSkeleton extends StatelessWidget
{
    /// 骨架卡片数量（默认 12 个，覆盖约 4 行）
    final int itemCount;

    const AlbumGridSkeleton({super.key, this.itemCount = 12});

    @override
    Widget build(BuildContext context)
    {
        // 高光色由主题派生：在 surfaceVariant 基础上向白色提亮 35%
        final baseColor = context.appColors.surfaceVariant;
        final highlightColor = Color.lerp(baseColor, Colors.white, 0.35)!;

        return Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            period: const Duration(milliseconds: 1200),
            child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.55,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) => const AlbumCardSkeleton(),
            ),
        );
    }
}
