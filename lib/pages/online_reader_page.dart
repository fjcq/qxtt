import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_service.dart';
import '../core/jm/jm_entity.dart';
import '../providers/browse_history_provider.dart';
import '../providers/download_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../utils/path_helper.dart';
import '../widgets/online_image_viewer.dart';
import 'reader/reader_base_mixin.dart';
import 'reader/reader_gesture_mixin.dart';
import 'reader/reader_ui_mixin.dart';

/// 在线阅读器页（统一阅读架构）
/// 流程:
/// 1. 获取 photo_detail + scramble_id + album_detail
/// 2. 调用 [DownloadService.ensureChapterDownloaded] 创建/复用章节下载任务
/// 3. 渲染时优先读本地文件，未下载页通过 [OnlineImageViewer] 占位并订阅下载事件
/// 4. 退出时保存阅读进度到 browse_history
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

  /// 当前页
  int _currentPage = 0;

  /// 当前是否正在初始加载
  bool _initialLoading = true;

  /// 本子下载根目录（探测一次）
  String? _downloadRoot;

  /// 当前章节本地保存目录（由 ensureChapterDownloaded 返回）
  String? _chapterSaveDir;



  @override
  String get initialPhotoId => widget.photoId;

  @override
  int get totalPages => _photoDetail?.pageArr.length ?? 0;

  @override
  int get currentPage => _currentPage;

  /// 更新当前页码
  ///
  /// 【性能优化】
  /// 不再触发 setState，仅同步 [_currentPage] 与 [currentPageNotifier]。
  /// UI（如底部进度条、页码显示）通过 [ValueListenableBuilder] 监听
  /// [currentPageNotifier] 局部重建，避免整个 reader 因页码变化而重建
  @override
  void setCurrentPage(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    currentPageNotifier.value = page;
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
      await client.getScrambleId(activePhotoId);

      AlbumDetail? albumDetail;
      try {
        albumDetail = await client.getAlbumDetail(detail.albumId);
      } catch (e) {
        debugPrint('[online_reader] getAlbumDetail(${detail.albumId}) 失败: $e');
        albumDetail = null;
      }

      if (!mounted) return;
      final initialPage = startPage.clamp(
        0,
        detail.pageArr.isEmpty ? 0 : detail.pageArr.length - 1,
      );
      setState(() {
        _photoDetail = detail;
        this.albumDetail = albumDetail;
        _currentPage = initialPage;
        _initialLoading = false;
      });
      currentPageNotifier.value = initialPage;

      if (startPage > 0 && scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToPage(startPage);
        });
      }

      // 【统一阅读架构】确保章节已下载，未下载页通过占位组件等待自动刷新
      await _ensureChapterDownloaded(activePhotoId);

      _preloadAdjacentChapters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        _initialLoading = false;
      });
    }
  }

  /// 确保当前章节已下载（统一阅读入口）
  ///
  /// 调用 [DownloadService.ensureChapterDownloaded]，拿到章节本地保存目录。
  /// 已完成 → 直接读本地；未完成 → 后台启动下载任务，单页完成事件由
  /// [OnlineImageViewer] 自行订阅刷新。
  Future<void> _ensureChapterDownloaded(String photoId) async
  {
    try
    {
      final downloadService = ref.read(downloadServiceProvider);
      final album = albumDetail;
      final episode = album != null ? findEpisodeInAlbum(photoId) : null;
      _chapterSaveDir = await downloadService.ensureChapterDownloaded(
        photoId: photoId,
        albumId: album?.albumId ?? photoId,
        title: album?.name ?? '',
        episodeIndex: episode?.index ?? '',
        episodeName: episode?.name ?? '',
      );
      if (mounted) setState(() {});
    }
    catch (e)
    {
      debugPrint('[online_reader] ensureChapterDownloaded 失败: $e');
    }
  }

  /// 切换到指定章节
  Future<void> _loadChapter(String photoId) async {
    setState(() {
      chapterLoading = true;
      error = null;
      _photoDetail = null;
      _currentPage = 0;
      _chapterSaveDir = null;
      activePhotoId = photoId;
    });
    currentPageNotifier.value = 0;

    final client = ref.read(jmClientProvider);

    try {
      final detail = await client.getPhotoDetail(photoId);
      await client.getScrambleId(photoId);

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
        chapterLoading = false;
      });

      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
      _persistProgressForChapter(photoId, 0);

      // 【统一阅读架构】章节切换同样触发 ensureChapterDownloaded
      await _ensureChapterDownloaded(photoId);

      _preloadAdjacentChapters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        chapterLoading = false;
      });
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

  /// 计算本地文件路径
  ///
  /// 【统一阅读架构】
  /// - 优先使用 [_chapterSaveDir]（由 ensureChapterDownloaded 返回）
  /// - 兜底回退到下载根目录 + photoId 单章直传目录
  /// - 实际存在性由 [OnlineImageViewer] 内部走 [FileExistenceCache] 异步检查
  String _buildLocalPath(int pageIndex) {
    final sep = Platform.pathSeparator;
    final seq = (pageIndex + 1).toString().padLeft(5, '0');
    final saveDir = _chapterSaveDir;
    if (saveDir != null && saveDir.isNotEmpty) {
      return '$saveDir$sep$seq.jpg';
    }
    // 兜底：单章直传目录
    final root = _downloadRoot;
    if (root == null) return '';
    return '$root$sep$activePhotoId$sep$seq.jpg';
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

  /// 构造单图 Widget（统一阅读架构：本地优先，未下载页占位）
  Widget _buildImageForIndex(int index, List<String> pages) {
    final localPath = _buildLocalPath(index);
    return OnlineImageViewer(
      key: ValueKey('${activePhotoId}_$index'),
      photoId: activePhotoId,
      filename: pages[index],
      localFilePath: localPath,
      pageIndex: index,
      totalPages: pages.length,
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
