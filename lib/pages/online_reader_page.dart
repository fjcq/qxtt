import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_entity.dart';
import '../core/jm/jm_image_loader.dart';
import '../providers/browse_history_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../utils/path_helper.dart';
import '../widgets/chapter_catalog_drawer.dart';
import '../widgets/online_image_viewer.dart';

/// 在线阅读器页
/// 流程:
/// 1. 获取 photo_detail + scramble_id
/// 2. 加载时优先尝试本地文件（如果整本已下载）
/// 3. 否则在线下载→解密→内存渲染
/// 4. 预加载当前页前后各 2 张
/// 5. 退出时保存阅读进度到 browse_history
///
/// 交互优化:
/// - PC端鼠标拖动+惯性滑动
/// - 键盘方向键控制（上下翻页，左右切换章节）
/// - 移动端双指缩放
/// - 左右滑动手势切换章节
/// - 进度条、章节导航、目录
class OnlineReaderPage extends ConsumerStatefulWidget
{
    /// 章节 ID
    final String photoId;

    const OnlineReaderPage({
        super.key,
        required this.photoId,
    });

    @override
    ConsumerState<OnlineReaderPage> createState() => _OnlineReaderPageState();
}

class _OnlineReaderPageState extends ConsumerState<OnlineReaderPage>
    with TickerProviderStateMixin
{
    /// 当前活跃的 photoId（章节切换时更新）
    String _activePhotoId = '';

    /// 章节详情
    PhotoDetail? _photoDetail;

    /// 本子详情（用于本地文件查找和章节导航）
    AlbumDetail? _albumDetail;

    /// scramble_id
    int _scrambleId = 0;

    /// 当前页
    int _currentPage = 0;

    /// 显示控制栏
    bool _showControls = true;

    /// 错误信息
    String? _error;

    /// 当前是否正在初始加载
    bool _initialLoading = true;

    /// 是否正在切换章节
    bool _chapterLoading = false;

    /// 本子下载根目录（探测一次）
    String? _downloadRoot;

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

    /// 全局缩放比例（移动端双指缩放，影响所有图片）
    double _globalScale = 1.0;

    /// 双指缩放：活跃指针（pointerId → 位置）
    final Map<int, Offset> _activePointers = {};

    /// 双指缩放：上一次两指间距
    double _lastPinchDistance = 0;

    /// 双击检测：上次点击时间
    DateTime? _lastTapTime;

    /// 水平滑动检测：是否已确认为水平滑动
    bool _isHorizontalDrag = false;

    /// 是否为桌面平台
    bool get _isDesktop =>
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    /// 当前章节在列表中的索引
    int get _currentEpisodeIndex
    {
        if (_albumDetail == null) return -1;
        for (var i = 0; i < _albumDetail!.episodes.length; i++)
        {
            if (_albumDetail!.episodes[i].photoId == _activePhotoId)
            {
                return i;
            }
        }
        return -1;
    }

    /// 是否有上一章
    bool get _hasPrevChapter
    {
        final idx = _currentEpisodeIndex;
        return idx > 0;
    }

    /// 是否有下一章
    bool get _hasNextChapter
    {
        final idx = _currentEpisodeIndex;
        return idx >= 0 && idx < (_albumDetail?.episodes.length ?? 0) - 1;
    }

    /// 当前章节名称
    String get _currentChapterName
    {
        if (_albumDetail == null) return '';
        for (final ep in _albumDetail!.episodes)
        {
            if (ep.photoId == _activePhotoId)
            {
                return ep.name;
            }
        }
        return '';
    }

    @override
    void initState()
    {
        super.initState();
        _activePhotoId = widget.photoId;
        _loadInitial();
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
        if (_photoDetail == null || !_scrollController.hasClients) return;

        final scrollOffset = _scrollController.offset;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final total = _photoDetail!.pageArr.length;

        if (maxScroll <= 0 || total <= 0) return;

        final estimatedPage = (scrollOffset / maxScroll * total).floor()
            .clamp(0, total - 1);

        if (estimatedPage != _currentPage)
        {
            setState(() => _currentPage = estimatedPage);
            _persistProgress();
        }
    }

    /// 初始加载章节信息和本地文件探测
    Future<void> _loadInitial() async
    {
        final client = ref.read(jmClientProvider);

        // 探测本地下载根目录
        try
        {
            _downloadRoot = await PathHelper.getDownloadDir();
        }
        catch (_)
        {
            _downloadRoot = null;
        }

        // 查询历史进度（用于恢复 lastReadPage）
        int startPage = 0;
        try
        {
            final history = await ref.read(browseHistoryDaoProvider).getAllHistory();
            for (final h in history)
            {
                if (h.lastReadPhotoId == _activePhotoId)
                {
                    startPage = h.lastReadPage;
                    break;
                }
            }
        }
        catch (_)
        {
            // 忽略
        }

        try
        {
            final detail = await client.getPhotoDetail(_activePhotoId);
            final scrambleId = await client.getScrambleId(_activePhotoId);

            // 尝试获取本子详情（用于章节导航和本地文件查找）
            AlbumDetail? albumDetail;
            try
            {
                albumDetail = await client.getAlbumDetail(detail.albumId);
            }
            catch (_)
            {
                albumDetail = null;
            }

            if (!mounted) return;
            setState(()
            {
                _photoDetail = detail;
                _albumDetail = albumDetail;
                _scrambleId = scrambleId;
                _currentPage = startPage.clamp(
                    0,
                    detail.pageArr.isEmpty ? 0 : detail.pageArr.length - 1,
                );
                _initialLoading = false;
            });

            // 恢复阅读位置
            if (startPage > 0 && _scrollController.hasClients)
            {
                WidgetsBinding.instance.addPostFrameCallback((_)
                {
                    _scrollToPage(startPage);
                });
            }

            // 预加载相邻章节信息
            _preloadAdjacentChapters();
        }
        catch (e)
        {
            if (!mounted) return;
            setState(()
            {
                _error = e.toString();
                _initialLoading = false;
            });
        }
    }

    /// 切换到指定章节
    Future<void> _loadChapter(String photoId) async
    {
        setState(()
        {
            _chapterLoading = true;
            _error = null;
            _photoDetail = null;
            _scrambleId = 0;
            _currentPage = 0;
            _activePhotoId = photoId;
        });

        final client = ref.read(jmClientProvider);

        try
        {
            final detail = await client.getPhotoDetail(photoId);
            final scrambleId = await client.getScrambleId(photoId);

            // 如果尚未获取本子详情，尝试获取
            if (_albumDetail == null)
            {
                try
                {
                    _albumDetail = await client.getAlbumDetail(detail.albumId);
                }
                catch (_)
                {
                    // 忽略
                }
            }

            if (!mounted) return;
            setState(()
            {
                _photoDetail = detail;
                _scrambleId = scrambleId;
                _chapterLoading = false;
            });

            // 滚动到顶部
            if (_scrollController.hasClients)
            {
                _scrollController.jumpTo(0);
            }
            _persistProgressForChapter(photoId, 0);

            // 预加载相邻章节信息
            _preloadAdjacentChapters();
        }
        catch (e)
        {
            if (!mounted) return;
            setState(()
            {
                _error = e.toString();
                _chapterLoading = false;
            });
        }
    }

    /// 预加载相邻章节信息（仅获取 PhotoDetail，不渲染）
    Future<void> _preloadAdjacentChapters() async
    {
        if (_albumDetail == null) return;
        final idx = _currentEpisodeIndex;
        final client = ref.read(jmClientProvider);

        // 预加载下一章
        if (idx >= 0 && idx < _albumDetail!.episodes.length - 1)
        {
            final nextPhotoId = _albumDetail!.episodes[idx + 1].photoId;
            // 异步预取，不阻塞 UI
            client.getPhotoDetail(nextPhotoId).catchError((_) => PhotoDetail(
                photoId: '',
                albumId: '',
            ));
        }
    }

    /// 切换到指定页
    void _setPage(int page)
    {
        if (_photoDetail == null) return;
        final max = _photoDetail!.pageArr.length - 1;
        if (page < 0 || page > max) return;
        _scrollToPage(page);
    }

    /// 滚动到指定页
    void _scrollToPage(int page)
    {
        if (!_scrollController.hasClients || _photoDetail == null) return;
        final total = _photoDetail!.pageArr.length;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (total <= 0 || maxScroll <= 0) return;

        final targetOffset = (page / (total - 1) * maxScroll).clamp(0.0, maxScroll);
        _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
        );
    }

    /// 持久化阅读进度
    Future<void> _persistProgress() async
    {
        if (_photoDetail == null) return;
        await _persistProgressForChapter(_activePhotoId, _currentPage);
    }

    /// 持久化指定章节的阅读进度
    Future<void> _persistProgressForChapter(String photoId, int page) async
    {
        if (_photoDetail == null) return;
        try
        {
            await ref.read(browseHistoryDaoProvider).updateReadProgress(
                _photoDetail!.albumId,
                page,
                photoId,
            );
        }
        catch (_)
        {
            // 忽略持久化失败
        }
    }

    /// 计算本地文件路径（如果已下载整本）
    String? _findLocalPath(int pageIndex)
    {
        if (_photoDetail == null || _downloadRoot == null) return null;
        final seq = (pageIndex + 1).toString().padLeft(5, '0');
        final sep = Platform.pathSeparator;

        // 1) 单章下载目录
        final photoDirPath = '$_downloadRoot$sep$_activePhotoId$sep$seq.jpg';
        if (File(photoDirPath).existsSync() &&
            File('$photoDirPath.ok').existsSync())
        {
            return photoDirPath;
        }

        // 2) 整本下载
        if (_albumDetail != null)
        {
            final episode = _findEpisodeInAlbum(_activePhotoId);
            if (episode != null)
            {
                final albumPath = PathHelper.getPagePath(
                    _downloadRoot!,
                    _albumDetail!.name,
                    episode.index,
                    pageIndex,
                );
                if (File(albumPath).existsSync() &&
                    File('$albumPath.ok').existsSync())
                {
                    return albumPath;
                }
            }
        }

        // 3) 退化扫描
        try
        {
            final root = Directory(_downloadRoot!);
            if (!root.existsSync()) return null;
            for (final entity in root.listSync(recursive: true))
            {
                if (entity is File &&
                    entity.path.endsWith('$seq.jpg') &&
                    entity.path.contains(_activePhotoId))
                {
                    return entity.path;
                }
            }
            return null;
        }
        catch (_)
        {
            return null;
        }
    }

    /// 在 albumDetail.episodes 中查找 photoId 对应的章节
    Episode? _findEpisodeInAlbum(String photoId)
    {
        if (_albumDetail == null) return null;
        for (final ep in _albumDetail!.episodes)
        {
            if (ep.photoId == photoId)
            {
                return ep;
            }
        }
        return null;
    }

    // ===== 指针事件（鼠标拖动 + 移动端双指缩放 + 水平滑动） =====

    /// 处理指针按下
    void _onPointerDown(PointerDownEvent event)
    {
        // 鼠标拖动
        if (event.kind == PointerDeviceKind.mouse)
        {
            _stopInertia();
            _isDragging = true;
            _lastPointerPosition = event.position;
            _dragVelocity = 0;
        }

        // 移动端触控：记录指针用于双指缩放
        if (!_isDesktop && event.kind == PointerDeviceKind.touch)
        {
            _activePointers[event.pointer] = event.position;
        }
    }

    /// 处理指针移动
    void _onPointerMove(PointerMoveEvent event)
    {
        // 鼠标拖动
        if (_isDragging && event.kind == PointerDeviceKind.mouse)
        {
            if (!_scrollController.hasClients) return;

            final delta = event.position - _lastPointerPosition;
            _lastPointerPosition = event.position;
            _dragVelocity = delta.dy;

            final newOffset = _scrollController.offset - delta.dy;
            final maxExtent = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(newOffset.clamp(0.0, maxExtent));
            return;
        }

        // 移动端双指缩放
        if (!_isDesktop && event.kind == PointerDeviceKind.touch)
        {
            _activePointers[event.pointer] = event.position;
            if (_activePointers.length == 2)
            {
                _handlePinchUpdate();
            }
        }
    }

    /// 处理指针释放
    void _onPointerUp(PointerUpEvent event)
    {
        // 鼠标拖动释放
        if (_isDragging && event.kind == PointerDeviceKind.mouse)
        {
            _isDragging = false;
            if (_dragVelocity.abs() > 5)
            {
                _startInertia(_dragVelocity);
            }
            return;
        }

        // 移动端触控释放
        if (!_isDesktop && event.kind == PointerDeviceKind.touch)
        {
            _activePointers.remove(event.pointer);
            if (_activePointers.length < 2)
            {
                _lastPinchDistance = 0;
                // 缩放比例过小时恢复为1
                if (_globalScale < 0.6)
                {
                    setState(() => _globalScale = 1.0);
                }
            }
        }
    }

    /// 处理指针取消
    void _onPointerCancel(PointerCancelEvent event)
    {
        if (!_isDesktop && event.kind == PointerDeviceKind.touch)
        {
            _activePointers.remove(event.pointer);
            if (_activePointers.length < 2)
            {
                _lastPinchDistance = 0;
            }
        }
    }

    /// 处理双指缩放更新
    void _handlePinchUpdate()
    {
        final pointers = _activePointers.values.toList();
        if (pointers.length < 2) return;

        final distance = (pointers[0] - pointers[1]).distance;
        if (_lastPinchDistance > 0)
        {
            final ratio = distance / _lastPinchDistance;
            final newScale = (_globalScale * ratio).clamp(0.5, 5.0);
            if (newScale != _globalScale)
            {
                setState(() => _globalScale = newScale);
            }
        }
        _lastPinchDistance = distance;
    }

    /// 单击/双击处理
    void _onTap()
    {
        final now = DateTime.now();
        if (_lastTapTime != null &&
            now.difference(_lastTapTime!).inMilliseconds < 300)
        {
            // 双击：切换缩放
            _lastTapTime = null;
            setState(()
            {
                _globalScale = _globalScale > 1.5 ? 1.0 : 2.0;
            });
        }
        else
        {
            _lastTapTime = now;
            // 单击：切换控制栏（延迟判断是否双击）
            Future.delayed(const Duration(milliseconds: 300), ()
            {
                if (_lastTapTime != null &&
                    DateTime.now().difference(_lastTapTime!).inMilliseconds >= 280)
                {
                    setState(() => _showControls = !_showControls);
                    _lastTapTime = null;
                }
            });
        }
    }

    /// 水平滑动开始
    void _onHorizontalDragStart(DragStartDetails details)
    {
        _isHorizontalDrag = true;
    }

    /// 水平滑动结束
    void _onHorizontalDragEnd(DragEndDetails details)
    {
        if (!_isHorizontalDrag) return;
        _isHorizontalDrag = false;

        final velocity = details.primaryVelocity ?? 0;
        // 向左快速滑动 → 下一章，向右快速滑动 → 上一章
        if (velocity < -300 && _hasNextChapter)
        {
            _goToNextChapter();
        }
        else if (velocity > 300 && _hasPrevChapter)
        {
            _goToPrevChapter();
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
        if (event is! KeyDownEvent && event is! KeyRepeatEvent)
        {
            return KeyEventResult.ignored;
        }

        const scrollStep = 300.0;

        // 左右方向键：切换章节
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft)
        {
            if (_hasPrevChapter)
            {
                _goToPrevChapter();
                return KeyEventResult.handled;
            }
        }
        else if (event.logicalKey == LogicalKeyboardKey.arrowRight)
        {
            if (_hasNextChapter)
            {
                _goToNextChapter();
                return KeyEventResult.handled;
            }
        }

        // 上下方向键：翻页
        if (!_scrollController.hasClients) return KeyEventResult.ignored;
        final currentOffset = _scrollController.offset;
        final maxExtent = _scrollController.position.maxScrollExtent;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp)
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
        else if (event.logicalKey == LogicalKeyboardKey.arrowDown)
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
                    onPointerCancel: _onPointerCancel,
                    child: GestureDetector(
                        onTap: _onTap,
                        onHorizontalDragStart: _onHorizontalDragStart,
                        onHorizontalDragEnd: _onHorizontalDragEnd,
                        child: Stack(
                            children: [
                                _buildContent(),
                                if (_chapterLoading) _buildChapterLoadingOverlay(),
                                if (_showControls && !_initialLoading &&
                                    !_chapterLoading && _error == null)
                                    _buildControls(),
                            ],
                        ),
                    ),
                ),
            ),
        );
    }

    /// 构建图片内容
    Widget _buildContent()
    {
        if (_initialLoading)
        {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
            );
        }
        if (_error != null)
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
                                _error!,
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
                                    setState(()
                                    {
                                        _initialLoading = true;
                                        _error = null;
                                    });
                                    _loadInitial();
                                },
                                child: const Text('重试'),
                            ),
                        ],
                    ),
                ),
            );
        }
        if (_photoDetail == null || _photoDetail!.pageArr.isEmpty)
        {
            return const Center(
                child: Text(
                    '暂无图片',
                    style: TextStyle(color: AppColors.textSecondary),
                ),
            );
        }

        final pages = _photoDetail!.pageArr;
        return _buildVerticalScroll(pages);
    }

    /// 构建章节切换加载遮罩
    Widget _buildChapterLoadingOverlay()
    {
        return Container(
            color: Colors.black54,
            child: Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        const CircularProgressIndicator(
                            color: AppColors.accent,
                            strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '正在切换章节...',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 构造单图 Widget（全局缩放通过调整图片宽度实现）
    Widget _buildImageForIndex(int index, List<String> pages)
    {
        final client = ref.watch(jmClientProvider);
        final loader = JmImageLoader(client);
        final aid = int.tryParse(_activePhotoId) ?? 0;
        final localPath = _findLocalPath(index);

        return OnlineImageViewer(
            key: ValueKey('${_activePhotoId}_$index'),
            photoId: _activePhotoId,
            filename: pages[index],
            scrambleId: _scrambleId,
            aid: aid,
            loader: loader,
            localFilePath: localPath,
            scale: _globalScale,
        );
    }

    /// 纵向滚动
    Widget _buildVerticalScroll(List<String> pages)
    {
        return ListView.builder(
            controller: _scrollController,
            itemCount: pages.length,
            scrollCacheExtent: ScrollCacheExtent.pixels(_isDesktop ? 800 : 400),
            itemBuilder: (context, index)
            {
                return _buildImageForIndex(index, pages);
            },
        );
    }

    /// 构建控制栏
    Widget _buildControls()
    {
        final total = _photoDetail?.pageArr.length ?? 0;
        final episodeName = _currentChapterName;

        return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                _buildTopBar(episodeName),
                _buildBottomBar(total),
            ],
        );
    }

    /// 构建顶部控制栏
    Widget _buildTopBar(String episodeName)
    {
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
                        onPressed: () async
                        {
                            await _persistProgress();
                            if (mounted) Navigator.of(context).pop();
                        },
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
                                    '${_currentPage + 1} / ${_photoDetail?.pageArr.length ?? 0}',
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
                        onPressed: _showCatalog,
                        tooltip: '目录',
                    ),
                ],
            ),
        );
    }

    /// 构建底部控制栏
    Widget _buildBottomBar(int total)
    {
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
                        _buildProgressBar(total),
                    const SizedBox(height: 8),
                    // 按钮行
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            // 上一章
                            IconButton(
                                icon: Icon(
                                    Icons.skip_previous,
                                    color: _hasPrevChapter
                                        ? Colors.white
                                        : Colors.white24,
                                ),
                                onPressed: _hasPrevChapter
                                    ? _goToPrevChapter
                                    : null,
                                tooltip: '上一章',
                            ),
                            const SizedBox(width: 16),
                            // 上一页
                            IconButton(
                                icon: const Icon(
                                    Icons.navigate_before,
                                    color: Colors.white,
                                ),
                                onPressed: _currentPage > 0
                                    ? () => _setPage(_currentPage - 1)
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
                                onPressed: _currentPage < total - 1
                                    ? () => _setPage(_currentPage + 1)
                                    : null,
                                tooltip: '下一页',
                            ),
                            const SizedBox(width: 16),
                            // 下一章
                            IconButton(
                                icon: Icon(
                                    Icons.skip_next,
                                    color: _hasNextChapter
                                        ? Colors.white
                                        : Colors.white24,
                                ),
                                onPressed: _hasNextChapter
                                    ? _goToNextChapter
                                    : null,
                                tooltip: '下一章',
                            ),
                        ],
                    ),
                ],
            ),
        );
    }

    /// 构建进度条
    Widget _buildProgressBar(int total)
    {
        return Row(
            children: [
                SizedBox(
                    width: 36,
                    child: Text(
                        '${_currentPage + 1}',
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
                                ? _currentPage / (total - 1)
                                : 0.0,
                            onChanged: (value)
                            {
                                final page = (value * (total - 1)).round();
                                _setPage(page);
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

    /// 跳转上一章
    void _goToPrevChapter()
    {
        final idx = _currentEpisodeIndex;
        if (idx > 0 && _albumDetail != null)
        {
            final prevPhotoId = _albumDetail!.episodes[idx - 1].photoId;
            _loadChapter(prevPhotoId);
        }
    }

    /// 跳转下一章
    void _goToNextChapter()
    {
        final idx = _currentEpisodeIndex;
        if (idx >= 0 && _albumDetail != null &&
            idx < _albumDetail!.episodes.length - 1)
        {
            final nextPhotoId = _albumDetail!.episodes[idx + 1].photoId;
            _loadChapter(nextPhotoId);
        }
    }

    /// 显示章节目录
    void _showCatalog()
    {
        if (_albumDetail == null || _albumDetail!.episodes.isEmpty) return;

        showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (context)
            {
                return ChapterCatalogDrawer(
                    episodes: _albumDetail!.episodes,
                    currentPhotoId: _activePhotoId,
                    onChapterSelected: (episode)
                    {
                        _loadChapter(episode.photoId);
                    },
                );
            },
        );
    }
}
