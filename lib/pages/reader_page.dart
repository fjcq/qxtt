import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/reader_provider.dart';
import '../core/jm/jm_image.dart';
import '../theme/app_colors.dart';

/// 离线阅读器页
/// 交互优化:
/// - PC端鼠标拖动+惯性滑动
/// - 键盘方向键控制
/// - 移动端双指缩放
/// - 进度条、翻页控制
class ReaderPage extends ConsumerStatefulWidget
{
    /// 章节 ID
    final String photoId;

    const ReaderPage({
        super.key,
        required this.photoId,
    });

    @override
    ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with TickerProviderStateMixin
{
    /// 滚动控制器
    final ScrollController _scrollController = ScrollController();

    /// 焦点节点（用于键盘事件）
    final FocusNode _focusNode = FocusNode();

    /// 鼠标拖动相关状态
    bool _isDragging = false;
    Offset _lastPointerPosition = Offset.zero;
    double _dragVelocity = 0;

    /// 惯性动画控制器
    AnimationController? _inertiaController;
    Animation<double>? _inertiaAnimation;

    /// 当前估算页码
    int _estimatedPage = 0;

    /// 是否为桌面平台
    bool get _isDesktop =>
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    @override
    void initState()
    {
        super.initState();
        Future.microtask(()
        {
            ref.read(readerProvider(widget.photoId).notifier).loadPages();
        });
        _scrollController.addListener(_onScroll);
    }

    @override
    void dispose()
    {
        _scrollController.removeListener(_onScroll);
        _scrollController.dispose();
        _inertiaController?.dispose();
        _focusNode.dispose();
        super.dispose();
    }

    /// 滚动监听，更新当前页码
    void _onScroll()
    {
        if (!_scrollController.hasClients) return;

        final state = ref.read(readerProvider(widget.photoId));
        if (state.imageUrls.isEmpty) return;

        final scrollOffset = _scrollController.offset;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final total = state.imageUrls.length;

        if (maxScroll <= 0 || total <= 0) return;

        final page = (scrollOffset / maxScroll * total).floor()
            .clamp(0, total - 1);

        if (page != _estimatedPage)
        {
            setState(() => _estimatedPage = page);
            ref.read(readerProvider(widget.photoId).notifier).setCurrentPage(page);
        }
    }

    // ===== 鼠标拖动 + 惯性 =====

    /// 处理鼠标按下
    void _onPointerDown(PointerDownEvent event)
    {
        if (event.kind != PointerDeviceKind.mouse) return;
        _stopInertia();
        _isDragging = true;
        _lastPointerPosition = event.position;
        _dragVelocity = 0;
    }

    /// 处理鼠标移动
    void _onPointerMove(PointerMoveEvent event)
    {
        if (!_isDragging || event.kind != PointerDeviceKind.mouse) return;
        if (!_scrollController.hasClients) return;

        final delta = event.position - _lastPointerPosition;
        _lastPointerPosition = event.position;
        _dragVelocity = delta.dy;

        final newOffset = _scrollController.offset - delta.dy;
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(newOffset.clamp(0.0, maxExtent));
    }

    /// 处理鼠标释放
    void _onPointerUp(PointerUpEvent event)
    {
        if (!_isDragging) return;
        _isDragging = false;

        if (_dragVelocity.abs() > 5)
        {
            _startInertia(_dragVelocity);
        }
    }

    /// 停止惯性动画
    void _stopInertia()
    {
        _inertiaController?.stop();
    }

    /// 启动惯性滑动动画
    void _startInertia(double velocity)
    {
        _inertiaController?.dispose();

        final distance = velocity * 8;
        final duration = (distance.abs() / 2000 * 1000).clamp(200, 800).toInt();

        _inertiaController = AnimationController(
            vsync: this,
            duration: Duration(milliseconds: duration),
        );

        final startOffset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;

        _inertiaAnimation = Tween<double>(
            begin: startOffset,
            end: startOffset - distance,
        ).animate(CurvedAnimation(
            parent: _inertiaController!,
            curve: Curves.decelerate,
        ));

        _inertiaAnimation!.addListener(_onInertiaUpdate);
        _inertiaController!.addStatusListener((status)
        {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed)
            {
                _inertiaAnimation?.removeListener(_onInertiaUpdate);
                _inertiaController?.dispose();
                _inertiaController = null;
                _inertiaAnimation = null;
            }
        });

        _inertiaController!.forward();
    }

    /// 惯性动画更新
    void _onInertiaUpdate()
    {
        if (!_scrollController.hasClients || _inertiaAnimation == null) return;
        final targetOffset = _inertiaAnimation!.value;
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(targetOffset.clamp(0.0, maxExtent));

        if (targetOffset <= 0 || targetOffset >= maxExtent)
        {
            _stopInertia();
        }
    }

    // ===== 键盘控制 =====

    /// 处理键盘事件
    KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event)
    {
        if (!_scrollController.hasClients) return KeyEventResult.ignored;
        if (event is! KeyDownEvent && event is! KeyRepeatEvent)
        {
            return KeyEventResult.ignored;
        }

        const scrollStep = 300.0;
        final currentOffset = _scrollController.offset;
        final maxExtent = _scrollController.position.maxScrollExtent;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft)
        {
            _stopInertia();
            final target = (currentOffset - scrollStep).clamp(0.0, maxExtent);
            _scrollController.animateTo(
                target,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
            );
            return KeyEventResult.handled;
        }
        else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)
        {
            _stopInertia();
            final target = (currentOffset + scrollStep).clamp(0.0, maxExtent);
            _scrollController.animateTo(
                target,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
            );
            return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
    }

    // ===== 构建界面 =====

    @override
    Widget build(BuildContext context)
    {
        final state = ref.watch(readerProvider(widget.photoId));

        return Scaffold(
            backgroundColor: Colors.black,
            body: Focus(
                focusNode: _focusNode,
                onKeyEvent: _onKeyEvent,
                autofocus: true,
                child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    child: GestureDetector(
                        onTap: () =>
                            ref.read(readerProvider(widget.photoId).notifier)
                                .toggleControls(),
                        child: Stack(
                            children: [
                                _buildContent(state),
                                if (state.showControls) _buildControls(state),
                            ],
                        ),
                    ),
                ),
            ),
        );
    }

    /// 构建图片内容
    Widget _buildContent(ReaderState state)
    {
        if (state.isLoading)
        {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
            );
        }

        if (state.error != null)
        {
            return Center(
                child: Text(
                    state.error!,
                    style: const TextStyle(color: AppColors.error),
                ),
            );
        }

        if (state.imageUrls.isEmpty)
        {
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
    Widget _buildVerticalScroll(ReaderState state)
    {
        return ListView.builder(
            controller: _scrollController,
            itemCount: state.imageUrls.length,
            scrollCacheExtent: ScrollCacheExtent.pixels(_isDesktop ? 800 : 400),
            itemBuilder: (context, index)
            {
                return _buildImageItem(state.imageUrls[index], index);
            },
        );
    }

    /// 构建单张图片（带缩放支持）
    Widget _buildImageItem(String url, int index)
    {
        final imageWidget = LayoutBuilder(
            builder: (context, constraints)
            {
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

        // 移动端支持双指缩放
        if (_isDesktop)
        {
            return imageWidget;
        }

        return _ZoomableImage(
            key: ValueKey('zoom_$index'),
            child: imageWidget,
        );
    }

    /// 构建控制栏
    Widget _buildControls(ReaderState state)
    {
        final total = state.totalPages;
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
                                    '${state.currentPage + 1} / $total',
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
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            // 进度条
                            if (total > 0)
                                _buildProgressBar(state, total),
                            const SizedBox(height: 8),
                            // 翻页按钮
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    IconButton(
                                        icon: const Icon(
                                            Icons.navigate_before,
                                            color: Colors.white,
                                        ),
                                        onPressed: state.currentPage > 0
                                            ? () => _scrollToPage(state.currentPage - 1, state)
                                            : null,
                                        tooltip: '上一页',
                                    ),
                                    const SizedBox(width: 24),
                                    IconButton(
                                        icon: const Icon(
                                            Icons.navigate_next,
                                            color: Colors.white,
                                        ),
                                        onPressed: state.currentPage < total - 1
                                            ? () => _scrollToPage(state.currentPage + 1, state)
                                            : null,
                                        tooltip: '下一页',
                                    ),
                                ],
                            ),
                        ],
                    ),
                ),
            ],
        );
    }

    /// 构建进度条
    Widget _buildProgressBar(ReaderState state, int total)
    {
        return Row(
            children: [
                SizedBox(
                    width: 36,
                    child: Text(
                        '${state.currentPage + 1}',
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
                            activeTrackColor: AppColors.accent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.accent,
                            overlayColor: AppColors.accent.withValues(alpha: 0.12),
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                            ),
                        ),
                        child: Slider(
                            value: total > 1
                                ? state.currentPage / (total - 1)
                                : 0.0,
                            onChanged: (value)
                            {
                                final page = (value * (total - 1)).round();
                                _scrollToPage(page, state);
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

    /// 滚动到指定页
    void _scrollToPage(int page, ReaderState state)
    {
        if (!_scrollController.hasClients) return;
        final total = state.totalPages;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (total <= 0 || maxScroll <= 0) return;

        final targetOffset = (page / (total - 1) * maxScroll).clamp(0.0, maxScroll);
        _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
        );
    }
}

/// 可缩放图片组件（移动端双指缩放）
class _ZoomableImage extends StatefulWidget
{
    /// 子组件
    final Widget child;

    const _ZoomableImage({
        super.key,
        required this.child,
    });

    @override
    State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
{
    /// 当前缩放比例
    double _scale = 1.0;

    /// 上次缩放比例
    double _previousScale = 1.0;

    /// 水平平移
    double _panX = 0;

    /// 垂直平移
    double _panY = 0;

    /// 是否正在缩放
    bool get _isZoomed => _scale > 1.05;

    @override
    Widget build(BuildContext context)
    {
        return GestureDetector(
            onScaleStart: (details)
            {
                _previousScale = _scale;
            },
            onScaleUpdate: (details)
            {
                setState(()
                {
                    _scale = (_previousScale * details.scale).clamp(1.0, 5.0);

                    if (_isZoomed)
                    {
                        _panX += details.focalPointDelta.dx;
                        _panY += details.focalPointDelta.dy;
                    }
                    else
                    {
                        _panX = 0;
                        _panY = 0;
                    }
                });
            },
            onScaleEnd: (details)
            {
                if (!_isZoomed)
                {
                    setState(()
                    {
                        _scale = 1.0;
                        _panX = 0;
                        _panY = 0;
                    });
                }
            },
            onDoubleTap: ()
            {
                setState(()
                {
                    if (_isZoomed)
                    {
                        _scale = 1.0;
                        _panX = 0;
                        _panY = 0;
                    }
                    else
                    {
                        _scale = 2.0;
                    }
                });
            },
            child: ClipRect(
                child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                        ..translateByDouble(_panX, _panY, 0.0, 1.0)
                        ..scaleByDouble(_scale, _scale, 1.0, 1.0),
                    child: widget.child,
                ),
            ),
        );
    }
}
