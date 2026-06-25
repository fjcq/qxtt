import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_entity.dart';
import '../core/reader/reader_download_engine.dart';
import '../providers/browse_history_provider.dart';
import '../providers/config_provider.dart';
import '../providers/reader_providers.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../utils/path_helper.dart';
import '../widgets/online_image_viewer.dart';
import 'reader/reader_base_mixin.dart';
import 'reader/reader_gesture_mixin.dart';
import 'reader/reader_ui_mixin.dart';

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
class OnlineReaderPage extends ConsumerStatefulWidget {
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
    with
        TickerProviderStateMixin<OnlineReaderPage>,
        ReaderBaseMixin<OnlineReaderPage>,
        ReaderGestureMixin<OnlineReaderPage>,
        ReaderUIMixin<OnlineReaderPage> {
  /// 章节详情
  PhotoDetail? _photoDetail;

  /// scramble_id
  int _scrambleId = 0;

  /// 当前页
  int _currentPage = 0;

  /// 当前是否正在初始加载
  bool _initialLoading = true;

  /// 本子下载根目录（探测一次）
  String? _downloadRoot;



  @override
  String get initialPhotoId => widget.photoId;

  @override
  int get totalPages => _photoDetail?.pageArr.length ?? 0;

  @override
  int get currentPage => _currentPage;

  @override
  void setCurrentPage(int page) {
    setState(() => _currentPage = page);
    // 页面稳定后预加载当前页前后范围
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadCurrentRange();
    });
  }

  @override
  bool get isLoading => _initialLoading;

  @override
  Future<void> loadInitial() => _loadInitial();

  @override
  Future<void> loadChapter(String photoId) => _loadChapter(photoId);

  @override
  Widget buildContent() => _buildContent();

  @override
  Widget buildImageForIndex(int index) =>
      _buildImageForIndex(index, _photoDetail!.pageArr);

  @override
  Future<void> persistProgress() async => _persistProgress();

  @override
  Future<void> onClose() async {
    await persistProgress();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Future<void> retryLoadAlbumDetail() => _retryLoadAlbumDetail();

  /// 初始加载章节信息和本地文件探测
  Future<void> _loadInitial() async {
    final client = ref.read(jmClientProvider);

    try {
      _downloadRoot = await PathHelper.getDownloadDir();
    } catch (_) {
      _downloadRoot = null;
    }

    int startPage = 0;
    try {
      final history = await ref.read(browseHistoryDaoProvider).getAllHistory();
      for (final h in history) {
        if (h.lastReadPhotoId == activePhotoId) {
          startPage = h.lastReadPage;
          break;
        }
      }
    } catch (_) {
      // 忽略
    }

    try {
      final detail = await client.getPhotoDetail(activePhotoId);
      final scrambleId = await client.getScrambleId(activePhotoId);

      AlbumDetail? albumDetail;
      try {
        albumDetail = await client.getAlbumDetail(detail.albumId);
      } catch (e) {
        debugPrint('[online_reader] getAlbumDetail(${detail.albumId}) 失败: $e');
        albumDetail = null;
      }

      if (!mounted) return;
      setState(() {
        _photoDetail = detail;
        this.albumDetail = albumDetail;
        _scrambleId = scrambleId;
        _currentPage = startPage.clamp(
          0,
          detail.pageArr.isEmpty ? 0 : detail.pageArr.length - 1,
        );
        _initialLoading = false;
      });

      if (startPage > 0 && scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToPage(startPage);
        });
      }

      _preloadAdjacentChapters();
      _preloadCurrentRange();
      _startSmartDownload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        _initialLoading = false;
      });
    }
  }

  /// 启动当前章节的智能下载（在线阅读自动保存到正式下载目录）
  Future<void> _startSmartDownload() async
  {
    try
    {
      final service = ref.read(smartDownloadServiceProvider);
      final episode = albumDetail != null
          ? findEpisodeInAlbum(activePhotoId)
          : null;

      unawaited(service.startSmartDownload(
        photoId: activePhotoId,
        albumTitle: albumDetail?.name ?? '',
        episodeIndex: episode?.index ?? '',
        episodeName: episode?.name ?? '',
        albumId: albumDetail?.albumId ?? activePhotoId,
      ));
    }
    catch (e)
    {
      debugPrint('[online_reader] 智能下载启动失败: $e');
    }
  }

  /// 切换到指定章节
  Future<void> _loadChapter(String photoId) async {
    setState(() {
      chapterLoading = true;
      error = null;
      _photoDetail = null;
      _scrambleId = 0;
      _currentPage = 0;
      activePhotoId = photoId;
    });

    final client = ref.read(jmClientProvider);

    try {
      final detail = await client.getPhotoDetail(photoId);
      final scrambleId = await client.getScrambleId(photoId);

      if (albumDetail == null) {
        try {
          albumDetail = await client.getAlbumDetail(detail.albumId);
        } catch (e) {
          debugPrint(
              '[online_reader] _loadChapter: getAlbumDetail(${detail.albumId}) 失败: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _photoDetail = detail;
        _scrambleId = scrambleId;
        chapterLoading = false;
      });

      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
      _persistProgressForChapter(photoId, 0);

      _preloadAdjacentChapters();
      _preloadCurrentRange();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        chapterLoading = false;
      });
    }
  }

  /// 预加载当前页前后范围内的图片（低优先级，不等待结果）
  Future<void> _preloadCurrentRange() async {
    if (_photoDetail == null) return;

    final pages = _photoDetail!.pageArr;
    if (pages.isEmpty) return;

    final loader = ref.read(readerImageLoaderProvider);
    final config = ref.read(configProvider).config;
    final range = config.preloadPageCount;
    final start = (_currentPage - range).clamp(0, pages.length - 1).toInt();
    final end = (_currentPage + range).clamp(0, pages.length - 1).toInt();
    final aid = int.tryParse(activePhotoId) ?? 0;

    for (var i = start; i <= end; i++) {
      if (i == _currentPage) continue;
      loader.preload(
        photoId: activePhotoId,
        filename: pages[i],
        scrambleId: _scrambleId,
        aid: aid,
      );
    }
  }

  /// 预加载相邻章节信息（仅获取 PhotoDetail，不渲染）
  Future<void> _preloadAdjacentChapters() async {
    if (albumDetail == null) return;
    final idx = currentEpisodeIndex;
    final client = ref.read(jmClientProvider);

    if (idx >= 0 && idx < albumDetail!.episodes.length - 1) {
      final nextPhotoId = albumDetail!.episodes[idx + 1].photoId;
      client.getPhotoDetail(nextPhotoId).catchError((_) => const PhotoDetail(
            photoId: '',
            albumId: '',
          ));
    }
  }

  /// 持久化阅读进度
  Future<void> _persistProgress() async {
    if (_photoDetail == null) return;
    await _persistProgressForChapter(activePhotoId, _currentPage);
  }

  /// 持久化指定章节的阅读进度
  Future<void> _persistProgressForChapter(String photoId, int page) async {
    if (_photoDetail == null) return;
    try {
      await ref.read(browseHistoryDaoProvider).updateReadProgress(
            _photoDetail!.albumId,
            page,
            photoId,
          );
    } catch (_) {
      // 忽略持久化失败
    }
  }

  /// 计算本地文件路径（如果已下载整本）
  ///
  /// 【性能优化】
  /// - 仅构造两个明确路径（整本目录 / 单章直传目录），不做同步 IO 检查
  /// - 实际存在性由 [OnlineImageViewer] 内部走 [FileExistenceCache] 异步检查
  /// - 删除原先的 `root.listSync(recursive: true)` 递归全盘扫描，
  ///   该操作在书架有几十个本子时可能耗时数百毫秒到数秒
  String? _findLocalPath(int pageIndex) {
    if (_photoDetail == null || _downloadRoot == null) return null;
    final sep = Platform.pathSeparator;
    final seq = (pageIndex + 1).toString().padLeft(5, '0');

    // 1. 整本下载目录优先：{downloadRoot}/{albumTitle}/{episodeIndex}/{seq}.jpg
    if (albumDetail != null) {
      final episode = findEpisodeInAlbum(activePhotoId);
      if (episode != null) {
        return PathHelper.getPagePath(
          _downloadRoot!,
          albumDetail!.name,
          episode.index,
          pageIndex,
        );
      }
    }

    // 2. 单章直传目录兜底：{downloadRoot}/{photoId}/{seq}.jpg
    return '$_downloadRoot$sep$activePhotoId$sep$seq.jpg';
  }

  /// 重试获取本子详情（用于章节导航）
  Future<void> _retryLoadAlbumDetail() async {
    if (_photoDetail == null) return;
    final client = ref.read(jmClientProvider);
    try {
      final albumDetail = await client.getAlbumDetail(_photoDetail!.albumId);
      if (!mounted) return;
      setState(() => this.albumDetail = albumDetail);
    } catch (e) {
      debugPrint('[online_reader] _retryLoadAlbumDetail 失败: $e');
    }
  }

  /// 构建图片内容
  Widget _buildContent() {
    if (_initialLoading) {
      return Center(
        child: CircularProgressIndicator(color: context.appColors.accent),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: context.appColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _initialLoading = true;
                    error = null;
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
    if (_photoDetail == null || _photoDetail!.pageArr.isEmpty) {
      return Center(
        child: Text(
          '暂无图片',
          style: TextStyle(color: context.appColors.textSecondary),
        ),
      );
    }

    final pages = _photoDetail!.pageArr;
    return _buildVerticalScroll(pages);
  }

  /// 构造单图 Widget（全局缩放通过调整图片宽度实现）
  Widget _buildImageForIndex(int index, List<String> pages) {
    final loader = ref.read(readerImageLoaderProvider);
    final config = ref.read(configProvider).config;
    final aid = int.tryParse(activePhotoId) ?? 0;
    final localPath = _findLocalPath(index);

    // 根据与当前页的距离分配下载优先级
    final distance = (index - _currentPage).abs();
    final priority = distance == 0
        ? DownloadPriority.immediate
        : distance <= config.preloadPageCount
            ? DownloadPriority.preload
            : DownloadPriority.background;

    return OnlineImageViewer(
      key: ValueKey('${activePhotoId}_$index'),
      photoId: activePhotoId,
      filename: pages[index],
      scrambleId: _scrambleId,
      aid: aid,
      loader: loader,
      localFilePath: localPath,
      priority: priority,
      scale: globalScale,
    );
  }

  /// 纵向滚动
  Widget _buildVerticalScroll(List<String> pages) {
    return ListView.builder(
      controller: scrollController,
      itemCount: pages.length,
      scrollCacheExtent: ScrollCacheExtent.pixels(isDesktop ? 800 : 400),
      itemBuilder: (context, index) {
        return buildImageForIndex(index);
      },
    );
  }
}
