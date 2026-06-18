import 'dart:developer' as developer;
import 'dart:io';

import '../data/models/library_album_model.dart';
import 'album_dir_scanner.dart';

/// 强制删除目录及处理散落封面文件的底层工具
class AlbumForceDelete
{
    AlbumForceDelete._();

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
                    '[LibraryStorage] delete attempt $attempt failed '
                    'for ${dir.path}: $e',
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
    static Future<void> tryDeleteLooseCover(
        LibraryAlbumModel album,
        String downloadDir,
        List<String> deletedAlbumPaths,
    ) async
    {
        if (album.coverPath.isEmpty) return;
        final coverFile = File(album.coverPath);
        if (!await coverFile.exists()) return;
        for (final dirPath in await AlbumDirScanner.collectAlbumDirs(
            album, downloadDir))
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
}
