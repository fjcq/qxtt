import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reader_base_mixin.dart';

/// 阅读器手势与键盘交互 mixin
///
/// 封装鼠标拖动、惯性滑动、双指缩放、单击/双击、水平滑动手势以及键盘控制。
/// 依赖 [ReaderBaseMixin] 提供滚动控制器、缩放比例、控制栏状态等基础能力。
mixin ReaderGestureMixin<T extends ConsumerStatefulWidget>
    on ReaderBaseMixin<T>, TickerProviderStateMixin<T> {
  // ==================== 手势相关状态 ====================

  /// 鼠标拖动相关状态
  bool _isDragging = false;
  Offset _lastPointerPosition = Offset.zero;
  double _dragVelocity = 0;

  /// 惯性动画控制器
  AnimationController? _inertiaController;
  Animation<double>? _inertiaAnimation;

  /// 双指缩放：活跃指针（pointerId → 位置）
  final Map<int, Offset> _activePointers = {};

  /// 双指缩放：上一次两指间距
  double _lastPinchDistance = 0;

  /// 双击检测：上次点击时间
  DateTime? _lastTapTime;

  /// 水平滑动检测：是否已确认为水平滑动
  bool _isHorizontalDrag = false;

  /// 水平滑动起始位置
  Offset? _horizontalDragStart;

  /// 水平滑动当前位置
  Offset? _horizontalDragCurrent;

  // ==================== 生命周期 ====================

  @override
  void dispose() {
    _inertiaController?.dispose();
    super.dispose();
  }

  // ==================== 指针事件（鼠标拖动 + 双指缩放） ====================

  /// 处理指针按下
  void onPointerDown(PointerDownEvent event) {
    // 鼠标拖动
    if (event.kind == PointerDeviceKind.mouse) {
      stopInertia();
      _isDragging = true;
      _lastPointerPosition = event.position;
      _dragVelocity = 0;
    }

    // 移动端触控：记录指针用于双指缩放
    if (!isDesktop && event.kind == PointerDeviceKind.touch) {
      _activePointers[event.pointer] = event.position;
    }
  }

  /// 处理指针移动
  void onPointerMove(PointerMoveEvent event) {
    // 鼠标拖动
    if (_isDragging && event.kind == PointerDeviceKind.mouse) {
      if (!scrollController.hasClients) return;

      final delta = event.position - _lastPointerPosition;
      _lastPointerPosition = event.position;
      _dragVelocity = delta.dy;

      final newOffset = scrollController.offset - delta.dy;
      final maxExtent = scrollController.position.maxScrollExtent;
      scrollController.jumpTo(newOffset.clamp(0.0, maxExtent));
      return;
    }

    // 移动端双指缩放
    if (!isDesktop && event.kind == PointerDeviceKind.touch) {
      _activePointers[event.pointer] = event.position;
      if (_activePointers.length == 2) {
        _handlePinchUpdate();
      }
    }
  }

  /// 处理指针释放
  void onPointerUp(PointerUpEvent event) {
    // 鼠标拖动释放
    if (_isDragging && event.kind == PointerDeviceKind.mouse) {
      _isDragging = false;
      if (_dragVelocity.abs() > 5) {
        _startInertia(_dragVelocity);
      }
      return;
    }

    // 移动端触控释放
    if (!isDesktop && event.kind == PointerDeviceKind.touch) {
      _activePointers.remove(event.pointer);
      if (_activePointers.length < 2) {
        _lastPinchDistance = 0;
        // 缩放比例过小时恢复为1
        if (globalScale < 0.6) {
          setState(() => globalScale = 1.0);
        }
      }
    }
  }

  /// 处理指针取消
  void onPointerCancel(PointerCancelEvent event) {
    if (!isDesktop && event.kind == PointerDeviceKind.touch) {
      _activePointers.remove(event.pointer);
      if (_activePointers.length < 2) {
        _lastPinchDistance = 0;
      }
    }
  }

  /// 处理双指缩放更新
  void _handlePinchUpdate() {
    final pointers = _activePointers.values.toList();
    if (pointers.length < 2) return;

    final distance = (pointers[0] - pointers[1]).distance;
    if (_lastPinchDistance > 0) {
      final ratio = distance / _lastPinchDistance;
      final newScale = (globalScale * ratio).clamp(0.5, 5.0);
      if (newScale != globalScale) {
        setState(() => globalScale = newScale);
      }
    }
    _lastPinchDistance = distance;
  }

  /// 单击/双击处理
  void onTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      // 双击：切换缩放
      _lastTapTime = null;
      setState(() {
        globalScale = globalScale > 1.5 ? 1.0 : 2.0;
      });
    } else {
      _lastTapTime = now;
      // 单击：切换控制栏（延迟判断是否双击）
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_lastTapTime != null &&
            DateTime.now().difference(_lastTapTime!).inMilliseconds >= 280) {
          setState(() {
            showControls = !showControls;
          });
          _lastTapTime = null;
        }
      });
    }
  }

  /// 水平滑动开始
  ///
  /// 【BUG 修复】
  /// 桌面端禁用水平滑动手势切章。桌面端鼠标垂直拖动滚动时，手抖常带有
  /// 水平分量（>50px），若松开时水平速度 > 300 会被误识别为切章手势，
  /// 导致意外返回上一章。桌面端切章通过左右方向键完成，移动端保留水平滑动。
  void onHorizontalDragStart(DragStartDetails details) {
    if (isDesktop) return;
    _isHorizontalDrag = true;
    _horizontalDragStart = details.localPosition;
    _horizontalDragCurrent = details.localPosition;
  }

  /// 水平滑动更新
  void onHorizontalDragUpdate(DragUpdateDetails details) {
    if (isDesktop) return;
    _horizontalDragCurrent = details.localPosition;
  }

  /// 水平滑动结束
  void onHorizontalDragEnd(DragEndDetails details) {
    if (isDesktop) return;
    if (!_isHorizontalDrag) return;
    _isHorizontalDrag = false;

    final start = _horizontalDragStart;
    final current = _horizontalDragCurrent;
    _horizontalDragStart = null;
    _horizontalDragCurrent = null;

    final velocity = details.primaryVelocity ?? 0;
    // 水平滑动距离需达到阈值，避免轻微误触触发切章
    var distanceOk = true;
    if (start != null && current != null) {
      final dx = (current.dx - start.dx).abs();
      distanceOk = dx >= 50;
    }

    // 向左快速滑动 → 下一章，向右快速滑动 → 上一章
    if (distanceOk && velocity < -300 && hasNextChapter) {
      goToNextChapter();
    } else if (distanceOk && velocity > 300 && hasPrevChapter) {
      goToPrevChapter();
    }
  }

  /// 停止惯性动画
  void stopInertia() {
    _inertiaController?.stop();
  }

  /// 启动惯性滑动动画
  void _startInertia(double velocity) {
    _inertiaController?.dispose();

    final distance = velocity * 8;
    final duration = (distance.abs() / 2000 * 1000).clamp(200, 800).toInt();

    _inertiaController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );

    final startOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;

    _inertiaAnimation = Tween<double>(
      begin: startOffset,
      end: startOffset - distance,
    ).animate(CurvedAnimation(
      parent: _inertiaController!,
      curve: Curves.decelerate,
    ));

    _inertiaAnimation!.addListener(_onInertiaUpdate);
    _inertiaController!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _inertiaAnimation?.removeListener(_onInertiaUpdate);
        _inertiaController?.dispose();
        _inertiaController = null;
        _inertiaAnimation = null;
      }
    });

    _inertiaController!.forward();
  }

  /// 惯性动画更新
  void _onInertiaUpdate() {
    if (!scrollController.hasClients || _inertiaAnimation == null) return;
    final targetOffset = _inertiaAnimation!.value;
    final maxExtent = scrollController.position.maxScrollExtent;
    scrollController.jumpTo(targetOffset.clamp(0.0, maxExtent));

    if (targetOffset <= 0 || targetOffset >= maxExtent) {
      stopInertia();
    }
  }

  // ==================== 键盘控制 ====================

  /// 处理键盘事件
  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    const scrollStep = 300.0;

    // 左右方向键：切换章节
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (hasPrevChapter) {
        goToPrevChapter();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (hasNextChapter) {
        goToNextChapter();
        return KeyEventResult.handled;
      }
    }

    if (!scrollController.hasClients) return KeyEventResult.ignored;
    final currentOffset = scrollController.offset;
    final maxExtent = scrollController.position.maxScrollExtent;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      stopInertia();
      final target = (currentOffset - scrollStep).clamp(0.0, maxExtent);
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      stopInertia();
      final target = (currentOffset + scrollStep).clamp(0.0, maxExtent);
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}
