import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 路径管理工具
class PathHelper
{
    /// 获取下载目录
    /// Android: /storage/emulated/0/Android/data/{package}/files/downloads
    /// iOS: {NSDocumentDirectory}/downloads
    static Future<String> getDownloadDir() async
    {
        final dir = await getApplicationDocumentsDirectory();
        final downloadDir = '${dir.path}${Platform.pathSeparator}downloads';
        await Directory(downloadDir).create(recursive: true);
        return downloadDir;
    }

    /// 获取漫画存储路径
    /// {downloadDir}/{漫画标题}/{章节序号}/
    static String getAlbumPath(String downloadDir, String title, String episode)
    {
        return '$downloadDir${Platform.pathSeparator}$title${Platform.pathSeparator}$episode';
    }

    /// 获取缓存目录
    static Future<String> getCacheDir() async
    {
        final dir = await getTemporaryDirectory();
        return dir.path;
    }

    /// 获取数据库目录
    static Future<String> getDatabaseDir() async
    {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
    }

    // 私有构造函数
    PathHelper._();
}
