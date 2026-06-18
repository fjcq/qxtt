import 'dart:io';

import '../data/models/library_album_model.dart';
import '../utils/cover_refresher.dart';
import '../utils/library_storage.dart';
import 'library_notifier_base.dart';
import 'search_provider.dart';

/// 书架写入与更新 mixin
/// 负责阅读进度、已下载章节标记、封面刷新等写操作
mixin LibraryWriteMixin on LibraryNotifierBase
{
    /// 更新阅读进度
    Future<void> updateReadProgress(
        String albumId,
        int page, {
        String? photoId,
    }) async
    {
        await libraryDao.updateReadProgress(albumId, page, photoId: photoId);
    }

    /// 标记章节已下载并刷新书架
    /// 当 coverPath 缺失或对应文件不存在时，自动用 localPath 下首张已下载图补封面
    Future<void> markEpisodesDownloaded(
        String albumId,
        Iterable<String> photoIds, {
        String? title,
        String? author,
        String? coverPath,
        String? localPath,
        int? pageCount,
        int? episodeCount,
    }) async
    {
        // 1) 优先使用调用方提供的 coverPath
        var resolvedCover = coverPath ?? '';

        // 2) coverPath 为空或对应文件不存在 → 尝试用本子目录下首张已下载图补封面
        final coverValid = resolvedCover.isNotEmpty &&
            await File(resolvedCover).exists();
        if (!coverValid && (localPath?.isNotEmpty ?? false))
        {
            final firstImg = await findFirstImage(localPath!);
            if (firstImg != null) resolvedCover = firstImg;
        }
        else if (!coverValid &&
            (title?.isNotEmpty ?? false) &&
            localPath == null)
        {
            // 兜底：localPath 为空时按 title 拼目录再找首张
            final downloadDir = await resolveDownloadDir();
            final temp = LibraryAlbumModel()
                ..albumId = albumId
                ..title = title!;
            final dir = await LibraryStorage.resolveAlbumDir(
                temp,
                downloadDir: downloadDir,
            );
            final firstImg = await findFirstImage(dir);
            if (firstImg != null) resolvedCover = firstImg;
        }

        await libraryDao.markEpisodesDownloaded(
            albumId,
            photoIds,
            title: title,
            author: author,
            coverPath: resolvedCover.isEmpty ? null : resolvedCover,
            localPath: localPath,
            pageCount: pageCount,
            episodeCount: episodeCount,
        );
        await loadLibrary();
    }

    /// 移除指定章节的已下载标记
    Future<void> removeDownloadedEpisodes(String albumId, Iterable<String> photoIds) async
    {
        await libraryDao.removeDownloadedEpisodes(albumId, photoIds);
        await loadLibrary();
    }

    /// 为单个本子补封面
    /// - 已有 cover 且文件存在 → 跳过
    /// - 本地有 cover.jpg → 直接回填
    /// - 远端拉取 → 保存到 <albumDir>/cover.jpg
    /// - 全失败 → 用本子首张已下载图兜底
    /// 完成后写回 DAO 并刷新 state
    Future<String> refreshCover(LibraryAlbumModel album) async
    {
        // 已有 cover 且文件存在
        if (album.coverPath.isNotEmpty && await File(album.coverPath).exists())
        {
            return album.coverPath;
        }

        // 解析本子目录
        final downloadDir = await resolveDownloadDir();
        final albumDir = await LibraryStorage.resolveAlbumDir(
            album,
            downloadDir: downloadDir,
        );
        final dirExists = await Directory(albumDir).exists();
        if (!dirExists) return '';

        // 本地已有 cover.jpg
        final localCover = File('$albumDir${Platform.pathSeparator}cover.jpg');
        if (await localCover.exists())
        {
            await libraryDao.updateAlbumCover(album.albumId, localCover.path);
            await loadLibrary();
            return localCover.path;
        }

        // 远端拉取
        final refresher = CoverRefresher(ref.read(jmClientProvider));
        final resolved = await refresher.refresh(album);
        if (resolved.isNotEmpty)
        {
            await libraryDao.updateAlbumCover(album.albumId, resolved);
            await loadLibrary();
        }
        return resolved;
    }

    /// 获取指定本子已下载章节 ID 集合
    Future<Set<String>> getDownloadedEpisodes(String albumId) async
    {
        return libraryDao.getDownloadedEpisodes(albumId);
    }
}
