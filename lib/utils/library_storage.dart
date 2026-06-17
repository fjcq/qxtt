import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/models/library_album_model.dart';

/// 单本漫画的本地占用统计
class AlbumDiskStats
{
    /// 占用的字节数
    final int sizeBytes;

    /// 文件数
    final int fileCount;

    const AlbumDiskStats({required this.sizeBytes, required this.fileCount});

    /// 0 值哨兵
    static const empty = AlbumDiskStats(sizeBytes: 0, fileCount: 0);
}

/// 已下载漫画的本地文件操作工具
/// 负责：计算占用、清理文件、扫描本地目录
class LibraryStorage
{
    // 私有构造函数
    LibraryStorage._();

    /// 获取应用下载根目录
    /// 优先使用配置中的 downloadDir，为空时回退到默认下载目录
    static Future<String> getDownloadDir({String configured = ''}) async
    {
        if (configured.isNotEmpty) return configured;
        return _getDefaultDownloadDir();
    }

    /// 获取默认下载目录（与 ConfigNotifier._initDefaultDownloadDir 保持一致）
    static Future<String> _getDefaultDownloadDir() async
    {
        final dir = await getApplicationDocumentsDirectory();
        final downloadDir = '${dir.path}${Platform.pathSeparator}downloads';
        await Directory(downloadDir).create(recursive: true);
        return downloadDir;
    }

    /// 解析本子对应的实际本地根目录
    /// 优先使用 album.localPath（下载时记录的真实路径），
    /// 为空时回退到 downloadDir/sanitizeFileName(title)
    static Future<String> resolveAlbumDir(
        LibraryAlbumModel album, {
        required String downloadDir,
    }) async
    {
        if (album.localPath.isNotEmpty) return album.localPath;
        final safeTitle = _sanitizeFileName(album.title);
        return '$downloadDir${Platform.pathSeparator}$safeTitle';
    }

    /// 计算指定目录的占用（字节 + 文件数）
    /// 目录不存在时返回 [AlbumDiskStats.empty]
    static Future<AlbumDiskStats> computeDiskUsage(String dirPath) async
    {
        final dir = Directory(dirPath);
        if (!await dir.exists()) return AlbumDiskStats.empty;

        var totalBytes = 0;
        var fileCount = 0;
        await for (final entity in dir.list(recursive: true, followLinks: false))
        {
            if (entity is File)
            {
                try
                {
                    totalBytes += await entity.length();
                    fileCount++;
                }
                catch (_)
                {
                    // 单个文件 stat 失败不阻塞整次统计
                }
            }
        }
        return AlbumDiskStats(sizeBytes: totalBytes, fileCount: fileCount);
    }

    /// 批量计算多本漫画的本地占用
    static Future<Map<String, AlbumDiskStats>> computeBatchDiskUsage(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        final result = <String, AlbumDiskStats>{};
        for (final album in albums)
        {
            final path = await resolveAlbumDir(album, downloadDir: downloadDir);
            result[album.albumId] = await computeDiskUsage(path);
        }
        return result;
    }

    /// 删除单本漫画的本地文件（彻底删除）
    /// 删除策略（按顺序尝试，每步失败不影响下一步）：
    /// 1) 严格尝试 album.localPath 与 downloadDir/<title>
    /// 2) 从 album.coverPath 父目录反推本子目录
    /// 3) 候选都不存在时，在 downloadDir 根目录下做模糊扫描
    ///    命中：目录名 === sanitize(title) / sanitize(albumId)
    ///          或顶层存在 cover.jpg（最宽松的兜底）
    /// 4) 对命中的目录做 _forceDelete：递归失败时重试 → Windows rmdir
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
        final candidates = await _collectAlbumDirs(album, downloadDir);
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
            final ok = await _forceDelete(dir);
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
            await _tryDeleteLooseCover(album, downloadDir, deletedPaths);
            return true;
        }

        // 第二步：模糊扫描，定位真正可能存放该 album 的目录
        final fuzzy = await _findAlbumDirsByScan(album, downloadDir);
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
            if (await _forceDelete(dir))
            {
                anyDeleted = true;
                deletedPaths.add(dirPath);
            }
        }
        if (anyDeleted)
        {
            await _tryDeleteLooseCover(album, downloadDir, deletedPaths);
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

    /// 收集所有明确已知的候选目录
    /// 包括：localPath、coverPath 反推、title 候选、albumId 候选
    static Future<Set<String>> _collectAlbumDirs(
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
                '$downloadDir${Platform.pathSeparator}${_sanitizeFileName(album.title)}',
            );
        }
        if (album.albumId.isNotEmpty)
        {
            set.add(
                '$downloadDir${Platform.pathSeparator}${_sanitizeFileName(album.albumId)}',
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
    static Future<List<String>> _findAlbumDirsByScan(
        LibraryAlbumModel album,
        String downloadDir,
    ) async
    {
        final hits = <String>[];
        final root = Directory(downloadDir);
        if (!await root.exists()) return hits;

        final expectNames = <String>{
            if (album.title.isNotEmpty) _sanitizeFileName(album.title),
            if (album.albumId.isNotEmpty) _sanitizeFileName(album.albumId),
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

    /// 强制删除目录：递归失败时多重兜底
    /// 1) 多次重试 recursive delete（应对 Windows 上文件占用释放延迟）
    /// 2) Windows 上用 rmdir /s /q 强删
    /// 3) 逐文件删除后删空目录
    /// 返回 true 表示目录已不存在
    /// 公开此方法供 DownloadNotifier 等其他模块复用
    static Future<bool> forceDelete(
        Directory dir, {
        int maxRetries = 4,
    }) async
    {
        return _forceDelete(dir, maxRetries: maxRetries);
    }

    /// 强制删除目录：递归失败时多重兜底
    /// 1) 多次重试 recursive delete（应对 Windows 上文件占用释放延迟）
    /// 2) Windows 上用 rmdir /s /q 强删
    /// 3) 逐文件删除后删空目录
    /// 返回 true 表示目录已不存在
    static Future<bool> _forceDelete(
        Directory dir, {
        int maxRetries = 4,
    }) async
    {
        if (!await dir.exists()) return true;

        // 第 1 步：多次重试 recursive delete
        for (var attempt = 0; attempt < maxRetries; attempt++)
        {
            try
            {
                await dir.delete(recursive: true);
                if (!await dir.exists()) return true;
            }
            catch (e)
            {
                developer.log(
                    '[LibraryStorage] delete attempt $attempt failed for ${dir.path}: $e',
                    name: 'jmcomic.library',
                );
            }
            // 等待文件占用释放
            await Future<void>.delayed(
                Duration(milliseconds: 150 * (attempt + 1)),
            );
        }

        // 第 2 步：Windows 上用 cmd rmdir 强删（绕过部分占用）
        if (Platform.isWindows)
        {
            try
            {
                final result = await Process.run(
                    'cmd',
                    ['/c', 'rmdir', '/s', '/q', dir.path],
                );
                developer.log(
                    '[LibraryStorage] rmdir exit=${result.exitCode} '
                    'stdout=${result.stdout} stderr=${result.stderr} '
                    'path=${dir.path}',
                    name: 'jmcomic.library',
                );
                if (!await dir.exists()) return true;
            }
            catch (e)
            {
                developer.log(
                    '[LibraryStorage] rmdir threw for ${dir.path}: $e',
                    name: 'jmcomic.library',
                );
            }
        }

        // 第 3 步：逐文件删除后再删空目录
        try
        {
            await for (final entity in dir.list(recursive: true, followLinks: false))
            {
                if (entity is File)
                {
                    try
                    {
                        await entity.delete();
                    }
                    catch (_)
                    {
                        // 跳过被占用的文件
                    }
                }
            }
            try
            {
                await dir.delete(recursive: true);
            }
            catch (_)
            {
                // 仍可能有残留
            }
        }
        catch (_)
        {
            // list 失败时不做任何事
        }

        final gone = !await dir.exists();
        developer.log(
            '[LibraryStorage] _forceDelete final path=${dir.path} gone=$gone',
            name: 'jmcomic.library',
        );
        return gone;
    }

    /// 尝试删除不在 albumDir 内的封面文件
    /// [deletedAlbumPaths] 已知被删的本子目录，用于判断 cover 是否在
    /// 已被清理的本子目录内（避免重复删除）
    static Future<void> _tryDeleteLooseCover(
        LibraryAlbumModel album,
        String downloadDir,
        List<String> deletedAlbumPaths,
    ) async
    {
        if (album.coverPath.isEmpty) return;
        final coverFile = File(album.coverPath);
        if (!await coverFile.exists()) return;
        for (final dirPath in await _collectAlbumDirs(album, downloadDir))
        {
            final coverDir = Directory(dirPath);
            try
            {
                if (await coverDir.exists() &&
                    album.coverPath.startsWith(
                        await coverDir.resolveSymbolicLinks(),
                    ))
                {
                    return;
                }
            }
            catch (_)
            {
                // 链接解析失败时继续尝试独立删除
            }
        }
        try
        {
            await coverFile.delete();
        }
        catch (_)
        {
            // ignore
        }
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
            final path = await resolveAlbumDir(album, downloadDir: downloadDir);
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
            if (await _forceDelete(entity))
            {
                removed.add(entity.path);
            }
        }
        return removed;
    }

    /// 将字节数格式化为可读字符串（KB/MB/GB）
    static String formatSize(int bytes)
    {
        if (bytes <= 0) return '0 B';
        if (bytes < 1024) return '$bytes B';
        if (bytes < 1024 * 1024)
        {
            return '${(bytes / 1024).toStringAsFixed(1)} KB';
        }
        if (bytes < 1024 * 1024 * 1024)
        {
            return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    /// 清理文件名中的非法字符
    /// 与 PathHelper.sanitizeFileName 规则保持一致
    static String _sanitizeFileName(String name)
    {
        var result = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        result = result.trimRight();
        while (result.endsWith('.'))
        {
            result = result.substring(0, result.length - 1);
        }
        if (result.isEmpty)
        {
            result = 'unnamed';
        }
        return result;
    }
}
