import 'dart:developer' as developer;
import 'dart:io';

import '../data/models/library_album_model.dart';
import 'album_dir_scanner.dart';
import 'album_force_delete.dart';
import 'album_path_resolver.dart';

/// 本子文件删除工具
/// 负责：删除单本/多本漫画本地文件、清理下载根目录下的孤儿目录
class AlbumFileDeleter
{
    AlbumFileDeleter._();

    /// 删除单本漫画的本地文件（彻底删除）
    /// 删除策略（按顺序尝试，每步失败不影响下一步）：
    /// 1) 严格尝试 album.localPath 与 downloadDir/<title>
    /// 2) 从 album.coverPath 父目录反推本子目录
    /// 3) 候选都不存在时，在 downloadDir 根目录下做模糊扫描
    ///    命中：目录名 === sanitize(title) / sanitize(albumId)
    ///          或顶层存在 cover.jpg（最宽松的兜底）
    /// 4) 对命中的目录做 AlbumForceDelete：递归失败时重试 → Windows rmdir
    ///    强删 → 逐文件删空目录
    /// 返回 true 表示：
    ///   - 至少有一个目录被删除，或
    ///   - 没有发现需要删除的目录（视为"已删"，如该 album 没有本地文件）
    /// 返回 false 表示发现需要删除的目录但删除失败
    static Future<bool> deleteAlbumFiles(
        LibraryAlbumModel album, {
        required String downloadDir,
    }) async
    {
        // 第一步：尝试已知候选路径
        final candidates = await AlbumDirScanner.collectAlbumDirs(
            album, downloadDir,
        );
        developer.log(
            '[LibraryStorage] deleteAlbumFiles albumId=${album.albumId} '
            'title=${album.title} localPath=${album.localPath} '
            'coverPath=${album.coverPath} '
            'downloadDir=$downloadDir candidates=$candidates',
            name: 'jmcomic.library',
        );
        var anyDeleted = false;
        final deletedPaths = <String>[];
        var anyCandidateExisted = false;
        for (final dirPath in candidates)
        {
            final dir = Directory(dirPath);
            final exists = await dir.exists();
            developer.log(
                '[LibraryStorage] try delete: $dirPath exists=$exists',
                name: 'jmcomic.library',
            );
            if (!exists) continue;
            anyCandidateExisted = true;
            final ok = await AlbumForceDelete.forceDelete(dir);
            developer.log(
                '[LibraryStorage] delete result: $dirPath ok=$ok',
                name: 'jmcomic.library',
            );
            if (ok)
            {
                anyDeleted = true;
                deletedPaths.add(dirPath);
            }
        }
        if (anyDeleted)
        {
            await AlbumForceDelete.tryDeleteLooseCover(
                album, downloadDir, deletedPaths,
            );
            return true;
        }

        // 第二步：模糊扫描，定位真正可能存放该 album 的目录
        final fuzzy = await AlbumDirScanner.findAlbumDirsByScan(
            album, downloadDir,
        );
        developer.log(
            '[LibraryStorage] fuzzy hits=$fuzzy',
            name: 'jmcomic.library',
        );
        for (final dirPath in fuzzy)
        {
            if (candidates.contains(dirPath)) continue;
            final dir = Directory(dirPath);
            if (!await dir.exists()) continue;
            anyCandidateExisted = true;
            if (await AlbumForceDelete.forceDelete(dir))
            {
                anyDeleted = true;
                deletedPaths.add(dirPath);
            }
        }
        if (anyDeleted)
        {
            await AlbumForceDelete.tryDeleteLooseCover(
                album, downloadDir, deletedPaths,
            );
            return true;
        }

        // 没有任何本地目录可删（候选都不存在、模糊扫描也没命中），
        // 视为"已删"——状态正确，无需清理
        if (!anyCandidateExisted)
        {
            return true;
        }
        // 有候选目录但全部删除失败
        return false;
    }

    /// 批量删除多本漫画的本地文件
    /// 返回 albumId -> 是否删除成功 的映射
    static Future<Map<String, bool>> deleteBatchAlbumFiles(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        final result = <String, bool>{};
        for (final album in albums)
        {
            result[album.albumId] =
                await deleteAlbumFiles(album, downloadDir: downloadDir);
        }
        return result;
    }

    /// 删除下载根目录下的孤儿文件
    /// 即不在 albums 列表对应目录中的文件夹
    /// 返回清理掉的目录名列表
    static Future<List<String>> cleanupOrphans(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        final root = Directory(downloadDir);
        if (!await root.exists()) return const [];

        final knownDirs = <String>{};
        for (final album in albums)
        {
            final path = await AlbumPathResolver.resolveAlbumDir(
                album, downloadDir: downloadDir,
            );
            knownDirs.add(Directory(path).uri.path);
        }

        final removed = <String>[];
        await for (final entity in root.list())
        {
            if (entity is! Directory) continue;
            if (knownDirs.contains(entity.uri.path))
            {
                continue;
            }
            if (await AlbumForceDelete.forceDelete(entity))
            {
                removed.add(entity.path);
            }
        }
        return removed;
    }
}
