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

/// 章节级 API 信息缓存（PhotoDetail + scrambleId）
/// 用于章节切换时复用已获取的网络数据，避免重复请求
class _ChapterApiInfo {
    /// 章节详情
    final PhotoDetail detail;

    /// 解密参数
    final int scrambleId;

    const _ChapterApiInfo(this.detail, this.scrambleId);
}

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
///
/// 【性能优化】
/// - **本地优先加载**：`_loadInitial` 先用本地元数据 + 本地扫描立即渲染首屏，
///   网络请求（getPhotoDetail/getAlbumDetail/getScrambleId）全部异步后台补充
/// - **章节 API 缓存**：按 photoId 缓存 PhotoDetail + scrambleId，
///   章节切换时复用缓存避免重复请求
/// - **批量文件检查**：`_buildMixedPageList` 一次性并行检查所有页的 .ok 标记
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

    /// 当前章节的 PhotoDetail（来自 API 或本地元数据，含全部页文件名）
    PhotoDetail? _activeChapterDetail;

    /// 当前章节的 scramble_id
    int _activeScrambleId = 0;

    /// 章节级 API 信息缓存：photoId -> (PhotoDetail + scrambleId)
    /// 切换章节时优先复用缓存，避免重复网络请求
    final Map<String, _ChapterApiInfo> _chapterApiCache = {};

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

    /// 初始加载（本地优先模式）
    ///
    /// 流程：
    /// 1. 解析下载目录
    /// 2. 从书架重建本子信息（含本地元数据 + 章节扩展元数据）
    /// 3. 用本地章节元数据初始化当前章节（pageArr + scrambleId），无网络即可渲染
    /// 4. 加载阅读进度
    /// 5. 加载章节图片（纯本地扫描 + 批量 .ok 检查）
    /// 6. 后台异步补充网络信息（不阻塞 UI）
    Future<void> _loadInitial() async {
        albumDetailFromApi = false;

        // 1. 解析下载目录
        try {
            await ref.read(configProvider.notifier).initialized;
            final configured = ref.read(configProvider).config.downloadDir;
            _downloadRoot =
                await LibraryStorage.getDownloadDir(configured: configured);
        } catch (_) {
            _downloadRoot = null;
        }

        // 2. 从书架重建本子信息（同步加载本地章节元数据）
        final matchedAlbum = await tryRebuildAlbumFromLibrary(_downloadRoot);
        if (matchedAlbum != null) {
            _currentAlbumId = matchedAlbum.albumId;
        }

        // 3. 用本地章节元数据初始化当前章节（无网络即可渲染）
        _applyLocalChapterMetadata(activePhotoId);

        // 4. 加载阅读进度
        await _loadSavedProgress();

        // 5. 加载章节图片（纯本地扫描 + 批量检查，无网络依赖）
        await _loadChapterImages(activePhotoId);

        // 6. 后台异步补充网络信息（不阻塞 UI）
        unawaited(_fetchNetworkInfoInBackground());
    }

    /// 用本地章节元数据初始化当前章节的 PhotoDetail + scrambleId
    /// 仅在本地元数据存在且当前缓存为空时生效
    void _applyLocalChapterMetadata(String photoId) {
        if (_chapterApiCache.containsKey(photoId)) {
            final cached = _chapterApiCache[photoId]!;
            _activeChapterDetail = cached.detail;
            _activeScrambleId = cached.scrambleId;
            return;
        }
        final localMeta = getLocalChapterMetadata(photoId);
        if (localMeta != null) {
            _activeChapterDetail = PhotoDetail(
                photoId: localMeta.photoId,
                albumId: _currentAlbumId,
                name: localMeta.name,
                pageArr: localMeta.pageArr,
            );
            _activeScrambleId = localMeta.scrambleId;
        }
    }

    /// 后台异步补充网络信息
    ///
    /// 获取当前章节的 PhotoDetail + scrambleId（验证本地元数据是否过期），
    /// 以及本子的 AlbumDetail（章节导航用）。失败不影响本地阅读。
    Future<void> _fetchNetworkInfoInBackground() async {
        final client = ref.read(jmClientProvider);
        try {
            final photoDetail = await client.getPhotoDetail(activePhotoId);
            int scrambleId = 0;
            try {
                scrambleId = await client.getScrambleId(activePhotoId);
            } catch (e) {
                debugPrint('[reader] getScrambleId($activePhotoId) 失败: $e');
            }
            _chapterApiCache[activePhotoId] =
                _ChapterApiInfo(photoDetail, scrambleId);

            // 本地元数据缺失或与网络不一致时，更新本地缓存并刷新页面
            final localMeta = getLocalChapterMetadata(activePhotoId);
            final localChanged = localMeta == null ||
                localMeta.scrambleId != scrambleId ||
                !_listEquals(localMeta.pageArr, photoDetail.pageArr);
            if (localChanged) {
                _activeChapterDetail = photoDetail;
                _activeScrambleId = scrambleId;
                if (mounted) {
                    await _refreshChapterPages(activePhotoId);
                }
            }
        } catch (e) {
            debugPrint('[reader] 后台 getPhotoDetail($activePhotoId) 失败: $e');
        }

        try {
            final albumId = _activeChapterDetail?.albumId ?? _currentAlbumId;
            if (albumId.isEmpty) return;
            final albumDetail = await client.getAlbumDetail(albumId);
            this.albumDetail = albumDetail;
            albumDetailFromApi = true;
            _currentAlbumId = albumDetail.albumId;
            if (mounted) setState(() {});
        } catch (e) {
            debugPrint('[reader] 后台 getAlbumDetail 失败: $e');
        }
    }

    /// 重新扫描本地并刷新当前章节的混合页列表
    /// 网络补充信息到达后调用，用于纠正本地元数据过期导致的页面列表差异
    Future<void> _refreshChapterPages(String photoId) async {
        final localPaths = await scanChapterImages(photoId, _downloadRoot);
        final localByIndex = <int, String>{};
        for (final p in localPaths) {
            final idx = _parseSeqIndexFromFileName(p);
            if (idx >= 0) {
                localByIndex[idx] = p;
            }
        }
        final pages = await _buildMixedPageList(
            photoId: photoId,
            localByIndex: localByIndex,
        );
        if (!mounted) return;
        setState(() {
            _chapterPages = pages;
        });
        unawaited(_preloadAdjacentChapters());
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
    /// 1. 通过本地元数据或 API 获取章节 [PhotoDetail]（含全部页文件名 + scramble_id）
    /// 2. 扫描本地目录，记录已下载完成的页码
    /// 3. 合并为 [ChapterPageItem] 列表（本地文件 + 网络回退）
    Future<void> _loadChapterImages(String photoId) async {
        setState(() {
            _isLoading = true;
            error = null;
            _chapterPages = [];
        });

        try {
            // 1. 拉取章节 API 信息（本地优先，无网络也能用）
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

            // 3. 构建混合页列表（批量并行检查 .ok 标记）
            final pages = await _buildMixedPageList(
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
    /// 【性能优化】
    /// - 优先复用 [_chapterApiCache] 缓存
    /// - 缓存未命中时优先使用本地元数据（无网络也能渲染）
    /// - 本地也缺失时才发网络请求；网络失败设置 detail 为 null，本地扫描仍可兜底
    Future<void> _ensureChapterApiInfo(String photoId) async {
        // 1. 缓存命中
        final cached = _chapterApiCache[photoId];
        if (cached != null) {
            _activeChapterDetail = cached.detail;
            _activeScrambleId = cached.scrambleId;
            return;
        }

        // 2. 本地元数据命中（无需网络）
        final localMeta = getLocalChapterMetadata(photoId);
        if (localMeta != null) {
            _activeChapterDetail = PhotoDetail(
                photoId: localMeta.photoId,
                albumId: _currentAlbumId,
                name: localMeta.name,
                pageArr: localMeta.pageArr,
            );
            _activeScrambleId = localMeta.scrambleId;
            // 后台异步补充网络信息，校验本地元数据是否过期
            unawaited(_fetchChapterInfoInBackground(photoId));
            return;
        }

        // 3. 本地缺失：同步等待网络请求（首次加载时不可避免）
        final client = ref.read(jmClientProvider);
        try {
            final detail = await client.getPhotoDetail(photoId);
            int scrambleId = 0;
            try {
                scrambleId = await client.getScrambleId(photoId);
            } catch (e) {
                debugPrint('[reader] getScrambleId($photoId) 失败: $e');
            }
            _chapterApiCache[photoId] = _ChapterApiInfo(detail, scrambleId);
            _activeChapterDetail = detail;
            _activeScrambleId = scrambleId;
        } catch (e) {
            debugPrint('[reader] getPhotoDetail($photoId) 失败: $e');
            _activeChapterDetail = null;
            _activeScrambleId = 0;
        }
    }

    /// 后台异步获取章节 API 信息（本地元数据已就绪时使用）
    /// 完成后若发现本地元数据过期则刷新页面
    Future<void> _fetchChapterInfoInBackground(String photoId) async {
        final client = ref.read(jmClientProvider);
        try {
            final detail = await client.getPhotoDetail(photoId);
            int scrambleId = 0;
            try {
                scrambleId = await client.getScrambleId(photoId);
            } catch (e) {
                debugPrint('[reader] getScrambleId($photoId) 失败: $e');
            }
            _chapterApiCache[photoId] = _ChapterApiInfo(detail, scrambleId);

            // 仅当当前章节仍是该 photoId 时才可能刷新
            if (activePhotoId != photoId) return;
            final localMeta = getLocalChapterMetadata(photoId);
            final localChanged = localMeta == null ||
                localMeta.scrambleId != scrambleId ||
                !_listEquals(localMeta.pageArr, detail.pageArr);
            if (localChanged && mounted) {
                _activeChapterDetail = detail;
                _activeScrambleId = scrambleId;
                await _refreshChapterPages(photoId);
            }
        } catch (e) {
            debugPrint('[reader] 后台 getPhotoDetail($photoId) 失败: $e');
        }
    }

    /// 构建混合页列表（异步 + 批量并行检查 .ok 标记）
    ///
    /// 【性能优化 P2】
    /// - 优先检查章节级 `.complete`：存在则整章本地，跳过逐页 stat
    /// - 章节未完成时回退到批量并行检查单页 `.ok`（兼容边下边看场景）
    Future<List<ChapterPageItem>> _buildMixedPageList({
        required String photoId,
        required Map<int, String> localByIndex,
    }) async {
        final pages = <ChapterPageItem>[];
        final detail = _activeChapterDetail;
        final aid = int.tryParse(photoId) ?? 0;
        final scrambleId = _activeScrambleId;

        // 优先检查章节级 .complete
        // 命中则整章本地，无需逐页 stat
        // 章节目录从 localByIndex 中任意一个路径的父目录推导
        String? chapterDir;
        if (localByIndex.isNotEmpty) {
            final anyPath = localByIndex.values.first;
            final sep = Platform.pathSeparator;
            final lastSep = anyPath.lastIndexOf(sep);
            if (lastSep > 0) {
                chapterDir = anyPath.substring(0, lastSep);
            }
        }
        // 若 localByIndex 为空，尝试用 _downloadRoot + photoId 兜底
        chapterDir ??= _downloadRoot != null
            ? '$_downloadRoot${Platform.pathSeparator}$photoId'
            : null;
        final chapterComplete = chapterDir != null &&
            await ChapterCompleteHelper.isChapterComplete(chapterDir);
        if (chapterComplete) {
            if (detail != null && detail.pageArr.isNotEmpty) {
                for (var i = 0; i < detail.pageArr.length; i++) {
                    final localPath = localByIndex[i];
                    if (localPath != null) {
                        pages.add(ChapterPageItem(
                            index: i,
                            localPath: localPath,
                            filename: detail.pageArr[i],
                            scrambleId: scrambleId,
                            aid: aid,
                        ));
                    } else {
                        pages.add(ChapterPageItem(
                            index: i,
                            localPath: null,
                            filename: detail.pageArr[i],
                            scrambleId: scrambleId,
                            aid: aid,
                        ));
                    }
                }
            } else {
                final indices = localByIndex.keys.toList()..sort();
                for (final i in indices) {
                    pages.add(ChapterPageItem(
                        index: i,
                        localPath: localByIndex[i],
                        filename: null,
                        scrambleId: scrambleId,
                        aid: aid,
                    ));
                }
            }
            return pages;
        }

        if (detail != null && detail.pageArr.isNotEmpty) {
            // 走 API：批量并行检查所有本地页的 .ok 标记
            final indices = List.generate(detail.pageArr.length, (i) => i);
            final localChecks = await Future.wait(
                indices.map((i) async {
                    final localPath = localByIndex[i];
                    if (localPath == null) return false;
                    return await isPageDownloaded(localPath);
                }),
            );
            for (var i = 0; i < detail.pageArr.length; i++) {
                final hasLocal = localChecks[i];
                final localPath = localByIndex[i];
                pages.add(ChapterPageItem(
                    index: i,
                    localPath: hasLocal ? localPath : null,
                    filename: detail.pageArr[i],
                    scrambleId: scrambleId,
                    aid: aid,
                ));
            }
        } else {
            // 无 API 信息：仅展示本地已下载的页（批量并行检查）
            final indices = localByIndex.keys.toList()..sort();
            final localChecks = await Future.wait(
                indices.map((i) async {
                    final localPath = localByIndex[i];
                    if (localPath == null) return false;
                    return await isPageDownloaded(localPath);
                }),
            );
            for (var k = 0; k < indices.length; k++) {
                if (localChecks[k]) {
                    final i = indices[k];
                    pages.add(ChapterPageItem(
                        index: i,
                        localPath: localByIndex[i],
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
            int scrambleId = 0;
            try {
                scrambleId = await client.getScrambleId(activePhotoId);
            } catch (e) {
                debugPrint('[reader] _retryLoadAlbumDetail: getScrambleId 失败: $e');
            }
            _chapterApiCache[activePhotoId] =
                _ChapterApiInfo(photoDetail, scrambleId);
            albumDetail = await client.getAlbumDetail(photoDetail.albumId);
            albumDetailFromApi = true;
            _currentAlbumId = albumDetail!.albumId;
            _activeChapterDetail = photoDetail;
            _activeScrambleId = scrambleId;
            if (mounted) {
                await _refreshChapterPages(activePhotoId);
                setState(() {});
            }
        } catch (e) {
            debugPrint('[reader] _retryLoadAlbumDetail 失败: $e');
        }
    }

    /// 切换到指定章节
    ///
    /// 【性能优化】
    /// - 不再强制清空 `_activeChapterDetail`，优先复用 [_chapterApiCache] 或本地元数据
    /// - 本地数据就绪时章节切换为纯本地操作，无网络请求
    Future<void> _loadChapter(String photoId) async {
        setState(() {
            chapterLoading = true;
            error = null;
        });

        _persistReadProgress(currentPage);

        try {
            // 优先复用缓存或本地元数据，避免强制网络请求
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

            final pages = await _buildMixedPageList(
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

            // 后台异步补充本子详情（用于章节导航）
            if (albumDetail == null) {
                unawaited(_fetchAlbumDetailInBackground(photoId));
            }
        } catch (e) {
            if (!mounted) return;
            setState(() {
                error = e.toString();
                chapterLoading = false;
            });
        }
    }

    /// 后台异步获取本子详情（章节切换时若本地缺失则补充）
    Future<void> _fetchAlbumDetailInBackground(String photoId) async {
        final client = ref.read(jmClientProvider);
        try {
            final detail = _chapterApiCache[photoId]?.detail ??
                await client.getPhotoDetail(photoId);
            if (activePhotoId != photoId) return;
            final albumDetail = await client.getAlbumDetail(detail.albumId);
            this.albumDetail = albumDetail;
            albumDetailFromApi = true;
            _currentAlbumId = albumDetail.albumId;
            if (mounted) setState(() {});
        } catch (e) {
            debugPrint('[reader] 后台 getAlbumDetail 失败: $e');
        }
    }

    /// 比较两个 List<String> 是否相等（顺序 + 内容）
    bool _listEquals(List<String> a, List<String> b) {
        if (identical(a, b)) return true;
        if (a.length != b.length) return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }
}
