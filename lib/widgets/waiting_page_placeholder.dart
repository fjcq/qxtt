import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 未下载页占位组件
///
/// 【统一阅读架构】
/// 阅读器只读本地文件，未下载页通过本组件呈现"等待下载"提示与进度。
/// 当下载事件到达时，父组件会刷新对应 [ChapterPageItem] 的本地路径，
/// 本组件随之被 [Image.file] 替换，无需自身监听事件。
///
/// - [pageIndex] 章节 0-based 页码，仅用于展示
/// - [progress] 章节整体下载进度 0.0~1.0；null 表示尚未开始
/// - [current] 已下载页数（与 [total] 配合显示具体计数）
/// - [total] 章节总页数
/// - [onPriorityDownload] 点击"优先下载"回调；为 null 时隐藏按钮
class WaitingPagePlaceholder extends StatelessWidget
{
    /// 章节 0-based 页码
    final int pageIndex;

    /// 章节整体进度；null 表示尚未开始
    final double? progress;

    /// 已下载页数
    final int current;

    /// 总页数
    final int total;

    /// 优先下载回调
    final VoidCallback? onPriorityDownload;

    const WaitingPagePlaceholder({
        super.key,
        required this.pageIndex,
        this.progress,
        this.current = 0,
        this.total = 0,
        this.onPriorityDownload,
    });

    @override
    Widget build(BuildContext context)
    {
        final colors = context.appColors;
        final hasProgress = progress != null && progress! > 0;
        final displayProgress = progress ?? 0.0;
        // 状态描述：未开始 / 下载中 / 已就绪（理论上不会出现"已就绪"，因为父级会切换为 Image.file）
        final statusText = progress == null
            ? '等待下载'
            : hasProgress
                ? '正在下载 $current/$total'
                : '准备下载';

        return Container(
            color: colors.background,
            constraints: const BoxConstraints(minHeight: 240),
            child: Center(
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                    ),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Icon(
                                Icons.downloading_outlined,
                                color: colors.textSecondary,
                                size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                                '第 ${pageIndex + 1} 页',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                                statusText,
                                style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                ),
                            ),
                            if (progress != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                        width: 200,
                                        child: LinearProgressIndicator(
                                            value: displayProgress.clamp(0.0, 1.0),
                                            backgroundColor: colors.surfaceVariant,
                                            color: colors.accent,
                                            minHeight: 2,
                                        ),
                                    ),
                                )
                            else
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            color: colors.accent,
                                            strokeWidth: 2,
                                        ),
                                    ),
                                ),
                            if (onPriorityDownload != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextButton.icon(
                                        icon: Icon(
                                            Icons.priority_high,
                                            color: colors.accent,
                                            size: 16,
                                        ),
                                        label: const Text('优先下载'),
                                        onPressed: onPriorityDownload,
                                    ),
                                ),
                        ],
                    ),
                ),
            ),
        );
    }
}
