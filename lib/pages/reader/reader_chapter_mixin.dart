import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/config_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../utils/library_storage.dart';
import 'reader_album_rebuild_mixin.dart';
import 'reader_base_mixin.dart';

/// 离线阅读器章节加载 mixin
///
/// 负责加载/切换章节、持久化阅读进度、预加载相邻章节等。
/// 依赖 [ReaderBaseMixin] 提供基础状态，[ReaderAlbumRebuildMixin] 提供本地目录扫描能力。
mixin ReaderChapterMixin<T extends ConsumerStatefulWidget>
    on ReaderBaseMixin<T>, ReaderAlbumRebuildMixin<T> {
  /// 当前本子的 albumId，用于持久化阅读进度
  String _currentAlbumId = '';

  /// 当前估算页码
  int _estimatedPage = 0;

  /// 书架记录中本子上次阅读的页码（用于恢复进度）
  int _savedLastReadPage = 0;

  /// 书架记录中本子上次阅读的章节 photoId（用于恢复进度）
  String _savedLastReadPhotoId = '';

  /// 是否正在加载
  bool _isLoading = true;

  /// 图片文件路径列表
  List<String> _imagePaths = [];

  /// 当前章节图片路径列表
  List<String> get imagePaths => _imagePaths;

  /// 下载根目录
  String? _downloadRoot;

  @override
  int get totalPages => _imagePaths.length;

  @override
  int get currentPage => _estimatedPage;

  @override
  void setCurrentPage(int page) => setState(() => _estimatedPage = page);

  @override
  bool get isLoading => _isLoading;

  @override
  Future<void> loadInitial() => _loadInitial();

  @override
  Future<void> loadChapter(String photoId) => _loadChapter(photoId);

  @override
  Future<void> persistProgress() async => _persistReadProgress(currentPage);

  @override
  Future<void> retryLoadAlbumDetail() => _retryLoadAlbumDetail();

  @override
  void dispose() {
    persistProgress();
    super.dispose();
  }

  /// 持久化当前阅读进度到书架
  void _persistReadProgress(int page) {
    if (_currentAlbumId.isEmpty) return;
    ref.read(libraryProvider.notifier).updateReadProgress(
          _currentAlbumId,
          page,
          photoId: activePhotoId,
        );
  }

  /// 初始加载
  Future<void> _loadInitial() async {
    albumDetailFromApi = false;

    try {
      await ref.read(configProvider.notifier).initialized;
      final configured = ref.read(configProvider).config.downloadDir;
      _downloadRoot =
          await LibraryStorage.getDownloadDir(configured: configured);
    } catch (_) {
      _downloadRoot = null;
    }

    try {
      final client = ref.read(jmClientProvider);
      final photoDetail = await client.getPhotoDetail(activePhotoId);
      try {
        albumDetail = await client.getAlbumDetail(photoDetail.albumId);
        _currentAlbumId = albumDetail!.albumId;
        albumDetailFromApi = true;
      } catch (e) {
        debugPrint('[reader] getAlbumDetail(${photoDetail.albumId}) 失败: $e');
        albumDetail = null;
        albumDetailFromApi = false;
      }
    } catch (e) {
      debugPrint('[reader] getPhotoDetail($activePhotoId) 失败: $e');
      albumDetail = null;
      albumDetailFromApi = false;
    }

    final matchedAlbum = await tryRebuildAlbumFromLibrary(_downloadRoot);
    if (matchedAlbum != null) {
      _currentAlbumId = matchedAlbum.albumId;
    }
    await _loadSavedProgress();
    await _loadChapterImages(activePhotoId);
  }

  /// 从书架加载本子上次阅读进度
  Future<void> _loadSavedProgress() async {
    if (_currentAlbumId.isEmpty) return;
    try {
      final album = await ref
          .read(libraryProvider.notifier)
          .getByAlbumId(_currentAlbumId);
      if (album != null) {
        _savedLastReadPage = album.lastReadPage;
        _savedLastReadPhotoId = album.lastReadPhotoId;
      }
    } catch (_) {
      // 忽略加载失败
    }
  }

  /// 加载指定章节的本地图片
  Future<void> _loadChapterImages(String photoId) async {
    setState(() {
      _isLoading = true;
      error = null;
      _imagePaths = [];
    });

    try {
      final paths = await scanChapterImages(photoId, _downloadRoot);
      if (!mounted) return;
      setState(() {
        _imagePaths = paths;
        _isLoading = false;
        activePhotoId = photoId;
      });

      if (scrollController.hasClients) {
        final shouldRestore = photoId == _savedLastReadPhotoId &&
            _savedLastReadPage > 0 &&
            _savedLastReadPage < paths.length;
        if (shouldRestore) {
          _estimatedPage = _savedLastReadPage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scrollToPage(_savedLastReadPage);
          });
        } else {
          _estimatedPage = 0;
          scrollController.jumpTo(0);
        }
      }

      unawaited(_preloadAdjacentChapters());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 后台预加载相邻章节的图片（只加载各章节前几张封面级图片）
  Future<void> _preloadAdjacentChapters() async {
    if (albumDetail == null) return;
    final episodes = albumDetail!.episodes;
    final currentIndex =
        episodes.indexWhere((ep) => ep.photoId == activePhotoId);
    if (currentIndex < 0) return;

    final preloadIds = <String>[];
    if (currentIndex > 0) {
      preloadIds.add(episodes[currentIndex - 1].photoId);
    }
    if (currentIndex < episodes.length - 1) {
      preloadIds.add(episodes[currentIndex + 1].photoId);
    }

    for (final photoId in preloadIds) {
      try {
        final paths = await scanChapterImages(photoId, _downloadRoot);
        for (final path in paths.take(3)) {
          final file = File(path);
          if (await file.exists()) {
            final imageProvider = FileImage(file);
            final stream = imageProvider.resolve(ImageConfiguration.empty);
            stream.addListener(ImageStreamListener((_, __) {}));
          }
        }
      } catch (_) {
        // 单章预加载失败不影响当前阅读
      }
    }
  }

  /// 重试获取本子详情（用于章节导航）
  Future<void> _retryLoadAlbumDetail() async {
    final client = ref.read(jmClientProvider);
    try {
      final photoDetail = await client.getPhotoDetail(activePhotoId);
      albumDetail = await client.getAlbumDetail(photoDetail.albumId);
      albumDetailFromApi = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[reader] _retryLoadAlbumDetail 失败: $e');
    }
  }

  /// 切换到指定章节
  Future<void> _loadChapter(String photoId) async {
    setState(() {
      chapterLoading = true;
      error = null;
    });

    _persistReadProgress(currentPage);

    try {
      final paths = await scanChapterImages(photoId, _downloadRoot);
      if (!mounted) return;
      setState(() {
        _imagePaths = paths;
        activePhotoId = photoId;
        chapterLoading = false;
        _estimatedPage = 0;
      });

      if (scrollController.hasClients) {
        final shouldRestore = photoId == _savedLastReadPhotoId &&
            _savedLastReadPage > 0 &&
            _savedLastReadPage < paths.length;
        if (shouldRestore) {
          _estimatedPage = _savedLastReadPage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            scrollToPage(_savedLastReadPage);
          });
        } else {
          _estimatedPage = 0;
          scrollController.jumpTo(0);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        chapterLoading = false;
      });
    }
  }
}
