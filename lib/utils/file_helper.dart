import 'dart:io';

/// 文件操作工具
class FileHelper
{
    /// 确保目录存在
    static Future<Directory> ensureDir(String path) async
    {
        final dir = Directory(path);
        if (!await dir.exists())
        {
            await dir.create(recursive: true);
        }
        return dir;
    }

    /// 删除目录
    static Future<void> deleteDir(String path) async
    {
        final dir = Directory(path);
        if (await dir.exists())
        {
            await dir.delete(recursive: true);
        }
    }

    /// 获取目录大小（字节）
    static Future<int> getDirSize(String path) async
    {
        final dir = Directory(path);
        if (!await dir.exists()) return 0;

        var size = 0;
        await for (final entity in dir.list(recursive: true))
        {
            if (entity is File)
            {
                size += await entity.length();
            }
        }
        return size;
    }

    /// 格式化文件大小
    static String formatSize(int bytes)
    {
        if (bytes < 1024) return '$bytes B';
        if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
        if (bytes < 1024 * 1024 * 1024)
        {
            return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
        return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }

    /// 获取目录下的文件列表
    static Future<List<File>> listFiles(String path, {String? extension}) async
    {
        final dir = Directory(path);
        if (!await dir.exists()) return [];

        final files = <File>[];
        await for (final entity in dir.list())
        {
            if (entity is File)
            {
                if (extension != null)
                {
                    if (entity.path.endsWith(extension))
                    {
                        files.add(entity);
                    }
                }
                else
                {
                    files.add(entity);
                }
            }
        }
        return files..sort((a, b) => a.path.compareTo(b.path));
    }

    // 私有构造函数
    FileHelper._();
}
