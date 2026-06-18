import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jm/jm_entity.dart';
import '../../data/models/library_album_model.dart';
import '../../providers/library_provider.dart';
import '../../utils/library_storage.dart';
import '../../utils/path_helper.dart';
import 'reader_base_mixin.dart';

/// 本地本子信息重建 mixin
///
/// 负责从书架与本地目录结构扫描图片、重建 [AlbumDetail] 与章节目录映射。
/// 依赖 [ReaderBaseMixin] 提供当前章节 ID 与本子详情状态。
mixin ReaderAlbumRebuildMixin<T extends ConsumerStatefulWidget> on ReaderBaseMixin<T>
{
    /// 本子详情是否来自网络 API
    bool _albumDetailFromApi = false;

    /// 本地重构的章节目录映射：photoId -> 图片目录绝对路径
    Map<String, String>? _localEpisodeDirs;

    /// 本子详情是否来自网络 API
    bool get albumDetailFromApi => _albumDetailFromApi;

    /// 设置本子详情来源标记
    set albumDetailFromApi(bool value) => _albumDetailFromApi = value;

    /// 扫描指定章节的本地图片文件
    Future<List<String>> scanChapterImages(
        String photoId,
        String? downloadRoot,
    ) async {
        if (downloadRoot == null) return [];

        final List<String> paths = [];
        final sep = Platform.pathSeparator;

        if (albumDetail != null && _albumDetailFromApi) {
            final episode = findEpisodeInAlbum(photoId);
            if (episode != null) {
                final albumDir = PathHelper.getAlbumPath(
                    downloadRoot,
                    PathHelper.sanitizeFileName(albumDetail!.name),
                    PathHelper.sanitizeFileName(episode.index),
                );
                paths.addAll(scanDirectoryForImages(albumDir));
            }
        }

        if (paths.isEmpty) {
            final localDirs = _localEpisodeDirs;
            if (localDirs != null && localDirs.containsKey(photoId)) {
                paths.addAll(scanDirectoryForImages(localDirs[photoId]!));
            }
        }

        if (paths.isEmpty) {
            final photoDir = '$downloadRoot$sep$photoId';
            paths.addAll(scanDirectoryForImages(photoDir));
        }

        return paths;
    }

    /// 获取指定章节内第 [pageIndex] 页的预期本地文件绝对路径
    ///
    /// 章节信息 [albumDetail] 已就绪且 [_albumDetailFromApi] 为 true 时，
    /// 根据本子标题与章节序号构造标准下载路径；否则尝试从 [localDirs] / 直传目录兜底。
    /// 返回 `null` 表示无法确定预期路径（需调用方走网络）。
    String? getExpectedLocalPathForPage(
        String photoId,
        int pageIndex,
        String? downloadRoot,
    ) {
        if (downloadRoot == null) return null;

        if (albumDetail != null && _albumDetailFromApi) {
            final episode = findEpisodeInAlbum(photoId);
            if (episode != null) {
                return PathHelper.getPagePath(
                    downloadRoot,
                    PathHelper.sanitizeFileName(albumDetail!.name),
                    PathHelper.sanitizeFileName(episode.index),
                    pageIndex,
                );
            }
        }

        final localDirs = _localEpisodeDirs;
        if (localDirs != null && localDirs.containsKey(photoId)) {
            final dir = localDirs[photoId]!;
            final seq = (pageIndex + 1).toString().padLeft(5, '0');
            return '$dir${Platform.pathSeparator}$seq.jpg';
        }

        // 单章节下载（直传 photoId 目录）
        final sep = Platform.pathSeparator;
        final seq = (pageIndex + 1).toString().padLeft(5, '0');
        return '$downloadRoot$sep$photoId$sep$seq.jpg';
    }

    /// 判断指定页码对应的本地文件是否已下载完成（包含 .ok 标记）
    bool isPageDownloaded(String? expectedPath) {
        if (expectedPath == null || expectedPath.isEmpty) return false;
        return File(expectedPath).existsSync() &&
            File('$expectedPath.ok').existsSync();
    }

    /// 扫描目录中的图片文件（按文件名排序）
    List<String> scanDirectoryForImages(String dirPath) {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) return [];

        final files = <File>[];
        try {
            for (final entity in dir.listSync()) {
                if (entity is File) {
                    final name = entity.path.toLowerCase();
                    if (name.endsWith('.jpg') ||
                        name.endsWith('.jpeg') ||
                        name.endsWith('.png') ||
                        name.endsWith('.webp')) {
                        files.add(entity);
                    }
                }
            }
        } catch (_) {
            return [];
        }

        files.sort((a, b) => a.path.compareTo(b.path));
        return files.map((f) => f.path).toList();
    }

    /// 从本地书架与目录结构加载/重建本子信息
    Future<LibraryAlbumModel?> tryRebuildAlbumFromLibrary(
        String? downloadRoot,
    ) async {
        if (downloadRoot == null) return null;

        final albums = await ref.read(libraryProvider.notifier).getAllAlbums();
        LibraryAlbumModel? matchedAlbum;
        for (final album in albums) {
            if (album.downloadedEpisodes.contains(activePhotoId)) {
                matchedAlbum = album;
                break;
            }
        }
        if (matchedAlbum == null) return null;

        final albumDir = await LibraryStorage.resolveAlbumDir(
            matchedAlbum,
            downloadDir: downloadRoot,
        );
        final dir = Directory(albumDir);
        if (!await dir.exists()) return matchedAlbum;

        final (metaDetail, metaDirs) =
            await LibraryStorage.loadAlbumMetadata(albumDir);
        if (metaDetail != null && metaDirs.isNotEmpty) {
            _localEpisodeDirs = metaDirs;
            albumDetail ??= metaDetail;
            return matchedAlbum;
        }

        final candidateDirs = <Directory>[];
        try {
            if (await directoryHasImages(albumDir)) {
                candidateDirs.add(dir);
            }
            await for (final entity in dir.list(followLinks: false)) {
                if (entity is! Directory) continue;
                final hasImages = await directoryHasImages(entity.path);
                if (hasImages) candidateDirs.add(entity);
            }
        } catch (_) {
            return matchedAlbum;
        }
        if (candidateDirs.isEmpty) return matchedAlbum;

        candidateDirs.sort((a, b) {
            final nameA = a.path.split(Platform.pathSeparator).last;
            final nameB = b.path.split(Platform.pathSeparator).last;
            return compareEpisodeIndex(nameA, nameB);
        });

        final episodes = <Episode>[];
        final localDirs = <String, String>{};
        final photoIds = matchedAlbum.downloadedEpisodes;
        for (var i = 0; i < photoIds.length && i < candidateDirs.length; i++) {
            final photoId = photoIds[i];
            final subDir = candidateDirs[i];
            final index = subDir.path.split(Platform.pathSeparator).last;
            episodes.add(Episode(
                photoId: photoId,
                index: index,
                name: '第 $index 话',
            ));
            localDirs[photoId] = subDir.path;
        }

        if (episodes.isEmpty) return matchedAlbum;

        albumDetail ??= AlbumDetail(
            albumId: matchedAlbum.albumId,
            name: matchedAlbum.title,
            author: matchedAlbum.author,
            pageCount: matchedAlbum.pageCount,
            episodeCount: matchedAlbum.episodeCount,
            episodes: episodes,
        );
        _localEpisodeDirs = localDirs;
        return matchedAlbum;
    }

    /// 比较章节目录名，优先按数字大小排序，非数字按字符串排序
    int compareEpisodeIndex(String a, String b) {
        final numA = int.tryParse(a);
        final numB = int.tryParse(b);
        if (numA != null && numB != null) {
            return numA.compareTo(numB);
        }
        return a.compareTo(b);
    }

    /// 判断目录中是否包含至少一张图片文件
    Future<bool> directoryHasImages(String dirPath) async {
        final dir = Directory(dirPath);
        if (!await dir.exists()) return false;
        try {
            await for (final entity in dir.list(followLinks: false)) {
                if (entity is File) {
                    final name = entity.path.toLowerCase();
                    if (name.endsWith('.jpg') ||
                        name.endsWith('.jpeg') ||
                        name.endsWith('.png') ||
                        name.endsWith('.webp')) {
                        return true;
                    }
                }
            }
        } catch (_) {
            return false;
        }
        return false;
    }
}
