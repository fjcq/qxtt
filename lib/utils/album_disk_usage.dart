import 'dart:io';

import '../data/models/library_album_model.dart';
import 'album_disk_stats.dart';
import 'album_path_resolver.dart';

/// 本地下载占用统计工具
class AlbumDiskUsage
{
    AlbumDiskUsage._();

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
            final path = await AlbumPathResolver.resolveAlbumDir(
                album, downloadDir: downloadDir,
            );
            result[album.albumId] = await computeDiskUsage(path);
        }
        return result;
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
}
