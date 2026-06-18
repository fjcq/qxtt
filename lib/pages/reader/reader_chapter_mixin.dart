import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jm/jm_entity.dart';
import '../../providers/config_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/search_provider.dart';
import '../../utils/library_storage.dart';
import 'chapter_page_item.dart';
import 'reader_album_rebuild_mixin.dart';
import 'reader_base_mixin.dart';

/// 离线阅读器章节加载 mixin
///
/// 负责加载/切换章节、持久化阅读进度、预加载相邻章节等。
/// 依赖 [ReaderBaseMixin] 提供基础状态，[ReaderAlbumRebuildMixin] 提供本地目录扫描能力。
///
/// 【边下边看支持】
/// 章节加载时优先通过 API 获取 [PhotoDetail]（含所有页的文件名），
/// 然后逐页判断本地是否已下载完成（.ok 标记），构建一份混合的 [ChapterPageItem] 列表：
/// - 本地存在 → 直接读本地文件
/// - 本地缺失 → 通过阅读下载引擎走网络
/// 这样既不阻塞下载进度，也保持与在线阅读一致的观看体验。
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

    /// 章节页面项列表（混合渲染：本地优先，缺失走网络）
    List<ChapterPageItem> _chapterPages = [];

    /// 当前章节的 PhotoDetail（来自 API，含全部页文件名）
    PhotoDetail? _activeChapterDetail;

    /// 当前章节的 scramble_id
    int _activeScrambleId = 0;

    /// 章节页面项列表
    List<ChapterPageItem> get chapterPages => _chapterPages;

    /// 当前章节的 PhotoDetail
    PhotoDetail? get activeChapterDetail => _activeChapterDetail;

    /// 兼容旧接口：仅返回本地文件路径
    List<String> get imagePaths => _chapterPages
        .where((p) => p.hasLocal)
        .map((p) => p.localPath!)
        .toList();

    /// 下载根目录
    String? _downloadRoot;

    @override
    int get totalPages => _chapterPages.length;

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

    /// 加载指定章节的混合页面列表
    ///
    /// 流程：
    /// 1. 通过 API 获取章节 [PhotoDetail]（含全部页文件名 + scramble_id）
    /// 2. 扫描本地目录，记录已下载完成的页码
    /// 3. 合并为 [ChapterPageItem] 列表（本地文件 + 网络回退）
    Future<void> _loadChapterImages(String photoId) async {
        setState(() {
            _isLoading = true;
            error = null;
            _chapterPages = [];
        });

        try {
            // 1. 拉取章节 API 信息
            await _ensureChapterApiInfo(photoId);

            // 2. 扫描本地已有图片
            final localPaths =
                await scanChapterImages(photoId, _downloadRoot);
            // 把本地路径转成 pageIndex 集合，文件名形如 00001.jpg
            final localByIndex = <int, String>{};
            for (final p in localPaths) {
                final idx = _parseSeqIndexFromFileName(p);
                if (idx >= 0) {
                    localByIndex[idx] = p;
                }
            }

            // 3. 构建混合页列表
            final pages = _buildMixedPageList(
                photoId: photoId,
                localByIndex: localByIndex,
            );

            if (!mounted) return;
            setState(() {
                _chapterPages = pages;
                _isLoading = false;
                activePhotoId = photoId;
            });

            if (scrollController.hasClients) {
                final shouldRestore = photoId == _savedLastReadPhotoId &&
                    _savedLastReadPage > 0 &&
                    _savedLastReadPage < pages.length;
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

    /// 确保当前章节的 API 信息（PhotoDetail + scramble_id）已加载
    ///
    /// 已有匹配的章节信息（photoId 相同）则直接复用，避免重复请求。
    /// 网络失败时设置 detail 为 null，本地扫描仍可作为兜底。
    Future<void> _ensureChapterApiInfo(String photoId) async {
        if (_activeChapterDetail != null &&
            _activeChapterDetail!.photoId == photoId) {
            return;
        }

        final client = ref.read(jmClientProvider);
        try {
            final detail = await client.getPhotoDetail(photoId);
            int scrambleId = 0;
            try {
                scrambleId = await client.getScrambleId(photoId);
            } catch (e) {
                debugPrint('[reader] getScrambleId($photoId) 失败: $e');
            }
            _activeChapterDetail = detail;
            _activeScrambleId = scrambleId;
        } catch (e) {
            debugPrint('[reader] getPhotoDetail($photoId) 失败: $e');
            _activeChapterDetail = null;
            _activeScrambleId = 0;
        }
    }

    /// 构建混合页列表
    List<ChapterPageItem> _buildMixedPageList({
        required String photoId,
        required Map<int, String> localByIndex,
    }) {
        final pages = <ChapterPageItem>[];
        final detail = _activeChapterDetail;
        final aid = int.tryParse(photoId) ?? 0;
        final scrambleId = _activeScrambleId;

        if (detail != null && detail.pageArr.isNotEmpty) {
            // 走 API：逐页构建，混合本地与网络
            for (var i = 0; i < detail.pageArr.length; i++) {
                final localPath = localByIndex[i];
                final hasLocal =
                    localPath != null && isPageDownloaded(localPath);
                pages.add(ChapterPageItem(
                    index: i,
                    localPath: hasLocal ? localPath : null,
                    filename: detail.pageArr[i],
                    scrambleId: scrambleId,
                    aid: aid,
                ));
            }
        } else {
            // 无 API 信息：仅展示本地已下载的页
            final indices = localByIndex.keys.toList()..sort();
            for (final i in indices) {
                final localPath = localByIndex[i];
                if (localPath != null && isPageDownloaded(localPath)) {
                    pages.add(ChapterPageItem(
                        index: i,
                        localPath: localPath,
                        filename: null,
                        scrambleId: scrambleId,
                        aid: aid,
                    ));
                }
            }
        }
        return pages;
    }

    /// 从本地文件路径中解析出页码（基于文件名 00001.jpg）
    int _parseSeqIndexFromFileName(String path) {
        final sep = Platform.pathSeparator;
        final name = path.split(sep).last;
        final dot = name.lastIndexOf('.');
        final seq = dot > 0 ? name.substring(0, dot) : name;
        final parsed = int.tryParse(seq);
        if (parsed == null) return -1;
        return parsed - 1; // 文件名从 1 开始，索引从 0 开始
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
                        final stream =
                            imageProvider.resolve(ImageConfiguration.empty);
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
            // 切换章节时强制重新拉取 API 信息
            _activeChapterDetail = null;
            _activeScrambleId = 0;
            await _ensureChapterApiInfo(photoId);

            final localPaths =
                await scanChapterImages(photoId, _downloadRoot);
            final localByIndex = <int, String>{};
            for (final p in localPaths) {
                final idx = _parseSeqIndexFromFileName(p);
                if (idx >= 0) {
                    localByIndex[idx] = p;
                }
            }

            final pages = _buildMixedPageList(
                photoId: photoId,
                localByIndex: localByIndex,
            );

            if (!mounted) return;
            setState(() {
                _chapterPages = pages;
                activePhotoId = photoId;
                chapterLoading = false;
                _estimatedPage = 0;
            });

            if (scrollController.hasClients) {
                final shouldRestore = photoId == _savedLastReadPhotoId &&
                    _savedLastReadPage > 0 &&
                    _savedLastReadPage < pages.length;
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
