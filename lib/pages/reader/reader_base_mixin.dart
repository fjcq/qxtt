import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/jm/jm_entity.dart';

/// 阅读器页面基础 mixin
///
/// 封装阅读器公共状态、生命周期、滚动控制与章节导航等基础能力。
/// 手势交互由 [ReaderGestureMixin] 扩展，UI 构建由 [ReaderUIMixin] 扩展。
mixin ReaderBaseMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  // ==================== 子类必须实现的抽象成员 ====================

  /// 页面传入的初始章节 ID
  String get initialPhotoId;

  /// 初始加载逻辑
  Future<void> loadInitial();

  /// 加载指定章节
  Future<void> loadChapter(String photoId);

  /// 总页数
  int get totalPages;

  /// 当前页码
  int get currentPage;

  /// 设置当前页码（仅更新状态，不触发滚动，不触发 setState）
  /// UI 通过 [currentPageNotifier] 监听变化自行重建
  void setCurrentPage(int page);

  /// 构建阅读内容主体（loading / error / 图片列表）
  Widget buildContent();

  /// 构建指定索引的图片
  Widget buildImageForIndex(int index);

  /// 持久化阅读进度
  Future<void> persistProgress();

  /// 是否处于初始加载中（控制栏显示条件）
  bool get isLoading;

  /// 返回/关闭页面时的处理
  Future<void> onClose();

  /// 重试获取本子详情
  Future<void> retryLoadAlbumDetail();

  // ==================== 公共状态字段 ====================

  /// 当前活跃的 photoId（章节切换时更新）
  String _activePhotoId = '';

  /// 本子详情（用于章节导航）
  AlbumDetail? _albumDetail;

  /// 是否显示控制栏
  bool _showControls = true;

  /// 错误信息
  String? _error;

  /// 是否正在切换章节
  bool _chapterLoading = false;

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 焦点节点（用于键盘事件）
  final FocusNode _focusNode = FocusNode();

  /// 当前页码的响应式 notifier
  /// UI（如底部进度条、页码显示）通过 [ValueListenableBuilder] 监听它，
  /// 页码变化时只重建这些局部组件，不触发整个 reader 重建。
  final ValueNotifier<int> _currentPageNotifier =
      ValueNotifier<int>(0);

  /// 持久化进度节流时间戳（毫秒）
  /// 滚动事件高频触发时，仅在距离上次持久化超过 [_kPersistThrottleMs] 时写库
  int _lastPersistMs = 0;

  /// 持久化进度节流间隔（毫秒）
  static const int _kPersistThrottleMs = 500;

  /// 全局缩放比例（移动端双指缩放，影响所有图片）
  double _globalScale = 1.0;

  // ==================== 公共 getter / setter ====================

  /// 当前活跃的章节 ID
  String get activePhotoId => _activePhotoId;

  /// 设置当前活跃的章节 ID
  set activePhotoId(String value) => _activePhotoId = value;

  /// 本子详情
  AlbumDetail? get albumDetail => _albumDetail;

  /// 设置本子详情
  set albumDetail(AlbumDetail? value) => _albumDetail = value;

  /// 是否显示控制栏
  bool get showControls => _showControls;

  /// 设置是否显示控制栏
  set showControls(bool value) => _showControls = value;

  /// 错误信息
  String? get error => _error;

  /// 设置错误信息
  set error(String? value) => _error = value;

  /// 是否正在切换章节
  bool get chapterLoading => _chapterLoading;

  /// 设置章节切换状态
  set chapterLoading(bool value) => _chapterLoading = value;

  /// 滚动控制器
  ScrollController get scrollController => _scrollController;

  /// 焦点节点
  FocusNode get focusNode => _focusNode;

  /// 当前页码 notifier（供 UI 用 ValueListenableBuilder 监听）
  ValueNotifier<int> get currentPageNotifier => _currentPageNotifier;

  /// 全局缩放比例
  double get globalScale => _globalScale;

  /// 设置全局缩放比例
  set globalScale(double value) => _globalScale = value;

  /// 是否为桌面平台
  bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// 当前章节在列表中的索引
  int get currentEpisodeIndex {
    if (_albumDetail == null) return -1;
    for (var i = 0; i < _albumDetail!.episodes.length; i++) {
      if (_albumDetail!.episodes[i].photoId == _activePhotoId) {
        return i;
      }
    }
    return -1;
  }

  /// 是否有上一章
  bool get hasPrevChapter {
    final idx = currentEpisodeIndex;
    return idx > 0;
  }

  /// 是否有下一章
  bool get hasNextChapter {
    final idx = currentEpisodeIndex;
    return idx >= 0 && idx < (_albumDetail?.episodes.length ?? 0) - 1;
  }

  /// 当前章节名称
  String get currentChapterName {
    if (_albumDetail == null) return '';
    for (final ep in _albumDetail!.episodes) {
      if (ep.photoId == _activePhotoId) {
        return ep.displayName;
      }
    }
    return '';
  }

  // ==================== 生命周期 ====================

  @override
  void initState() {
    super.initState();
    _activePhotoId = initialPhotoId;
    loadInitial();
    _scrollController.addListener(_onScroll);
    // 阅读时保持屏幕常亮（仅移动端需要，桌面端无自动息屏场景）
    if (!isDesktop) {
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    // 离开阅读器时恢复系统息屏策略
    if (!isDesktop) {
      WakelockPlus.disable();
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  // ==================== 滚动与进度 ====================

  /// 滚动监听，根据滚动位置更新当前页码并持久化进度
  ///
  /// 【性能优化】
  /// - [setCurrentPage] 不再触发 setState，只更新 [currentPageNotifier]，
  ///   UI（如底部进度条）通过 ValueListenableBuilder 局部重建
  /// - [persistProgress] 节流：滚动高频触发时，距离上次写库超过
  ///   [_kPersistThrottleMs] 才真正执行，避免每帧写 SQLite
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final total = totalPages;
    if (total <= 0) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final page = (_scrollController.offset / maxScroll * total)
        .floor()
        .clamp(0, total - 1);

    if (page != currentPage) {
      setCurrentPage(page);
      _maybePersistProgress();
    }
  }

  /// 节流持久化进度
  /// 章节切换/dispose 时调用 [persistProgress] 立即生效
  void _maybePersistProgress() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPersistMs < _kPersistThrottleMs) return;
    _lastPersistMs = now;
    persistProgress();
  }

  /// 滚动到指定页
  ///
  /// [instant] 为 true 时使用 [ScrollController.jumpTo] 无动画跳转，
  /// 适用于进度条拖动场景，避免与下一次 onChange 的 animateTo 冲突产生抖动；
  /// 默认 false 使用 [ScrollController.animateTo] 平滑动画，适用于翻页按钮。
  void scrollToPage(int page, {bool instant = false}) {
    if (!_scrollController.hasClients) return;
    final total = totalPages;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (total <= 0 || maxScroll <= 0) return;

    final targetOffset = (page / (total - 1) * maxScroll).clamp(0.0, maxScroll);
    if (instant) {
      _scrollController.jumpTo(targetOffset);
      return;
    }
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  // ==================== 章节导航 ====================

  /// 在 albumDetail.episodes 中查找 photoId 对应的章节
  Episode? findEpisodeInAlbum(String photoId) {
    if (_albumDetail == null) return null;
    for (final ep in _albumDetail!.episodes) {
      if (ep.photoId == photoId) {
        return ep;
      }
    }
    return null;
  }

  /// 跳转上一章
  Future<void> goToPrevChapter() async {
    final idx = currentEpisodeIndex;
    if (idx > 0 && _albumDetail != null) {
      final prevPhotoId = _albumDetail!.episodes[idx - 1].photoId;
      await loadChapter(prevPhotoId);
    }
  }

  /// 跳转下一章
  Future<void> goToNextChapter() async {
    final idx = currentEpisodeIndex;
    if (idx >= 0 &&
        _albumDetail != null &&
        idx < _albumDetail!.episodes.length - 1) {
      final nextPhotoId = _albumDetail!.episodes[idx + 1].photoId;
      await loadChapter(nextPhotoId);
    }
  }
}
