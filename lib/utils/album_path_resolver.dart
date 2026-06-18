import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/models/library_album_model.dart';

/// 本地下载路径解析与文件名清理工具
class AlbumPathResolver
{
    AlbumPathResolver._();

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
        final safeTitle = sanitizeFileName(album.title);
        return '$downloadDir${Platform.pathSeparator}$safeTitle';
    }

    /// 清理文件名中的非法字符
    /// 与 PathHelper.sanitizeFileName 规则保持一致
    static String sanitizeFileName(String name)
    {
        var result = name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
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
