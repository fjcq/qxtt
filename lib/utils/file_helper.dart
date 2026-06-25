import 'dart:io';

/// 异步文件存在性缓存
///
/// 在下载等高频文件检查场景中，避免重复的同步 IO 操作阻塞事件循环。
/// 缓存结果在 [_cacheTimeout] 内有效，写入文件后应调用 [invalidate] 清除。
class FileExistenceCache
{
    static final Map<String, bool> _cache = {};
    static final Map<String, DateTime> _cacheTime = {};
    static const Duration _cacheTimeout = Duration(seconds: 5);

    /// 异步检查文件是否存在（带缓存）
    static Future<bool> fileExists(String path) async
    {
        final now = DateTime.now();
        if (_cache.containsKey(path))
        {
            final cachedTime = _cacheTime[path];
            if (cachedTime != null && now.difference(cachedTime) < _cacheTimeout)
            {
                return _cache[path]!;
            }
        }

        try
        {
            final exists = await File(path).exists();
            _cache[path] = exists;
            _cacheTime[path] = now;
            return exists;
        }
        catch (_)
        {
            return false;
        }
    }

    /// 使指定路径的缓存失效（文件写入/删除后调用）
    static void invalidate(String path)
    {
        _cache.remove(path);
        _cacheTime.remove(path);
    }

    /// 清除所有缓存
    static void clear()
    {
        _cache.clear();
        _cacheTime.clear();
    }

    FileExistenceCache._();
}

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
