import 'dart:io';

import '../data/models/library_album_model.dart';
import 'album_path_resolver.dart';

/// 本地下载目录扫描工具
/// 负责根据 album 信息定位可能存放该本子的本地目录
class AlbumDirScanner
{
    AlbumDirScanner._();

    /// 收集所有明确已知的候选目录
    /// 包括：localPath、coverPath 反推、title 候选、albumId 候选
    static Future<Set<String>> collectAlbumDirs(
        LibraryAlbumModel album,
        String downloadDir,
    ) async
    {
        final set = <String>{};
        if (album.localPath.isNotEmpty) set.add(album.localPath);

        // 从 coverPath 反推本子目录（最可靠的"权威位置"）
        final coverBasedDirs = await _dirsDerivedFromCover(album);
        for (final p in coverBasedDirs)
        {
            set.add(p);
        }

        if (album.title.isNotEmpty)
        {
            set.add(
                '$downloadDir${Platform.pathSeparator}'
                '${AlbumPathResolver.sanitizeFileName(album.title)}',
            );
        }
        if (album.albumId.isNotEmpty)
        {
            set.add(
                '$downloadDir${Platform.pathSeparator}'
                '${AlbumPathResolver.sanitizeFileName(album.albumId)}',
            );
        }
        return set;
    }

    /// 从 coverPath 反推本子目录
    /// DownloadService 中 cover 可能写在两种位置：
    ///   1) <downloadDir>/<safeTitle>/cover.jpg  → 父目录就是本子目录
    ///   2) <downloadDir>/<safeTitle>/<safeEpisodeIndex>/00001.jpg（兜底图）
    ///      → 父目录的父目录才是本子目录
    static Future<List<String>> _dirsDerivedFromCover(
        LibraryAlbumModel album,
    ) async
    {
        final result = <String>[];
        if (album.coverPath.isEmpty) return result;
        try
        {
            final file = File(album.coverPath);
            if (!await file.exists()) return result;
            final dir = file.parent;
            // 直接父目录作为候选
            result.add(dir.path);
            // 父目录的父目录（兜底图场景）也作为候选
            if (dir.parent.path.isNotEmpty && dir.parent.path != dir.path)
            {
                result.add(dir.parent.path);
            }
        }
        catch (_)
        {
            // 忽略
        }
        return result;
    }

    /// 在 downloadDir 下扫描定位真正可能存放该 album 的目录
    /// 命中条件（任一）：
    /// - 目录名 === sanitize(title) 或 sanitize(albumId)
    /// - 顶层存在 cover.jpg（最宽松的兜底，认 cover 即认本子）
    /// 命中后不再做"是否含图片"校验（封面缺失或被清空也不应阻止删除）
    static Future<List<String>> findAlbumDirsByScan(
        LibraryAlbumModel album,
        String downloadDir,
    ) async
    {
        final hits = <String>[];
        final root = Directory(downloadDir);
        if (!await root.exists()) return hits;

        final expectNames = <String>{
            if (album.title.isNotEmpty)
                AlbumPathResolver.sanitizeFileName(album.title),
            if (album.albumId.isNotEmpty)
                AlbumPathResolver.sanitizeFileName(album.albumId),
        };
        // coverPath 父目录的目录名也加入候选
        if (album.coverPath.isNotEmpty)
        {
            try
            {
                final coverFile = File(album.coverPath);
                if (await coverFile.exists())
                {
                    final dirName = coverFile.parent.uri.pathSegments.isNotEmpty
                        ? coverFile.parent.uri.pathSegments.last
                        : '';
                    if (dirName.isNotEmpty) expectNames.add(dirName);
                    // 父目录的父目录名（兜底图场景）
                    final grand = coverFile.parent.parent;
                    final grandName = grand.uri.pathSegments.isNotEmpty
                        ? grand.uri.pathSegments.last
                        : '';
                    if (grandName.isNotEmpty &&
                        grandName != dirName &&
                        grand.path != root.path)
                    {
                        expectNames.add(grandName);
                    }
                }
            }
            catch (_)
            {
                // ignore
            }
        }

        await for (final entity in root.list(followLinks: false))
        {
            if (entity is! Directory) continue;
            if (hits.contains(entity.path)) continue;
            final name = entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last
                : '';

            // 1) 目录名匹配
            if (expectNames.contains(name))
            {
                hits.add(entity.path);
                continue;
            }

            // 2) 顶层有 cover.jpg → 强识别为"本子目录"
            final coverAtRoot =
                File('${entity.path}${Platform.pathSeparator}cover.jpg');
            if (await coverAtRoot.exists())
            {
                hits.add(entity.path);
            }
        }
        return hits;
    }
}
