import 'dart:io';

import 'file_helper.dart';

/// 章节级完成标记工具
///
/// 【性能优化 P2】
/// 用单个章节级 `.complete` 标记替代每页的 `.ok` 标记，
/// 减少文件碎片化（每章 30 页 → 1 个标记文件，而非 30 个 .ok）。
///
/// 兼容策略：
/// - 章节下载完成时写 `.complete`，删除所有 `.ok`
/// - 加载时优先检查 `.complete`，存在则整章本地有效
/// - 边下边看场景（章节未完成）：仍按单页 `.ok` 判断
/// - 应用启动时扫描下载目录，将旧版 `.ok` 全完整的章节迁移为 `.complete`
class ChapterCompleteHelper
{
    ChapterCompleteHelper._();

    /// 章节完成标记文件名
    static const completeFileName = '.complete';

    /// 获取章节完成标记文件路径
    static String getCompletePath(String chapterDir)
    {
        return '$chapterDir${Platform.pathSeparator}$completeFileName';
    }

    /// 判断章节是否完整下载（含 `.complete` 标记）
    /// 走 [FileExistenceCache] 5s 缓存，避免高频 stat
    static Future<bool> isChapterComplete(String chapterDir) async
    {
        return await FileExistenceCache.fileExists(getCompletePath(chapterDir));
    }

    /// 写入章节完成标记（含预期页数，便于断点续传校验）
    static Future<void> markChapterComplete(
        String chapterDir,
        int pageCount,
    ) async
    {
        try
        {
            final file = File(getCompletePath(chapterDir));
            await file.parent.create(recursive: true);
            await file.writeAsString('$pageCount', flush: true);
            // 失效缓存，让后续读取看到新文件
            FileExistenceCache.invalidate(getCompletePath(chapterDir));
        }
        catch (_)
        {
            // 写入失败不阻塞下载主流程
        }
    }

    /// 读取章节预期页数（用于断点续传校验）
    /// 返回 null 表示无 `.complete` 文件或读取失败
    static Future<int?> readExpectedPageCount(String chapterDir) async
    {
        try
        {
            final file = File(getCompletePath(chapterDir));
            if (!await file.exists()) return null;
            final content = await file.readAsString();
            return int.tryParse(content.trim());
        }
        catch (_)
        {
            return null;
        }
    }

    /// 删除章节完成标记
    static Future<void> clearChapterComplete(String chapterDir) async
    {
        try
        {
            final file = File(getCompletePath(chapterDir));
            if (await file.exists())
            {
                await file.delete();
                FileExistenceCache.invalidate(getCompletePath(chapterDir));
            }
        }
        catch (_)
        {
            // 忽略删除失败
        }
    }

    /// 删除章节目录下所有页的 `.ok` 标记
    /// 章节级 `.complete` 已写入后调用，清理碎片
    static Future<void> removeAllOkMarks(String chapterDir) async
    {
        try
        {
            final dir = Directory(chapterDir);
            if (!await dir.exists()) return;
            await for (final entity in dir.list(followLinks: false))
            {
                if (entity is File && entity.path.toLowerCase().endsWith('.ok'))
                {
                    try
                    {
                        await entity.delete();
                        FileExistenceCache.invalidate(entity.path);
                    }
                    catch (_)
                    {
                        // 忽略单个删除失败
                    }
                }
            }
        }
        catch (_)
        {
            // 忽略目录扫描失败
        }
    }

    /// 迁移旧版 `.ok` 标记到 `.complete`
    ///
    /// 规则：若章节目录中所有 `.jpg` 都有对应 `.ok`，且无 `.complete`，
    /// 则写 `.complete`，并删除所有 `.ok` 文件。
    /// 返回是否完成了迁移（true 表示已迁移，false 表示无需迁移或失败）
    static Future<bool> migrateOkToComplete(String chapterDir) async
    {
        try
        {
            final dir = Directory(chapterDir);
            if (!await dir.exists()) return false;

            final completePath = getCompletePath(chapterDir);
            if (await File(completePath).exists()) return false;

            // 扫描所有 .jpg 和 .ok 文件
            final jpgFiles = <File>[];
            final okFiles = <File>[];
            await for (final entity in dir.list(followLinks: false))
            {
                if (entity is File)
                {
                    final name = entity.path.toLowerCase();
                    if (name.endsWith('.ok'))
                    {
                        okFiles.add(entity);
                    }
                    else if (name.endsWith('.jpg') || name.endsWith('.jpeg'))
                    {
                        jpgFiles.add(entity);
                    }
                }
            }

            if (jpgFiles.isEmpty) return false;

            // 检查每个 .jpg 是否都有 .ok
            final okPaths = Set<String>.from(okFiles.map((f) => f.path));
            for (final jpg in jpgFiles)
            {
                if (!okPaths.contains('${jpg.path}.ok'))
                {
                    // 有 .jpg 没有 .ok → 未完整下载，不迁移
                    return false;
                }
            }

            // 全部都有 .ok → 写 .complete
            await markChapterComplete(chapterDir, jpgFiles.length);

            // 删除所有 .ok
            for (final ok in okFiles)
            {
                try
                {
                    await ok.delete();
                    FileExistenceCache.invalidate(ok.path);
                }
                catch (_)
                {
                    // 忽略单个删除失败
                }
            }
            return true;
        }
        catch (_)
        {
            return false;
        }
    }

    /// 批量迁移下载根目录下所有章节的 `.ok` 标记
    /// 应在应用启动时调用一次（fire-and-forget），后台异步执行不阻塞 UI
    static Future<void> migrateAllChapters(String downloadRoot) async
    {
        try
        {
            final root = Directory(downloadRoot);
            if (!await root.exists()) return;

            // 两层目录结构：{album}/{episode}/
            await for (final albumDir in root.list(followLinks: false))
            {
                if (albumDir is! Directory) continue;
                await for (final episodeDir in albumDir.list(followLinks: false))
                {
                    if (episodeDir is! Directory) continue;
                    await migrateOkToComplete(episodeDir.path);
                }
            }

            // 单章直传目录结构：{photoId}/
            await for (final photoDir in root.list(followLinks: false))
            {
                if (photoDir is! Directory) continue;
                // 跳过上面已处理的本子目录
                final hasSubDirs = await _hasSubDirectory(photoDir);
                if (!hasSubDirs)
                {
                    await migrateOkToComplete(photoDir.path);
                }
            }
        }
        catch (_)
        {
            // 迁移失败不阻塞应用启动
        }
    }

    /// 判断目录是否包含子目录
    static Future<bool> _hasSubDirectory(Directory dir) async
    {
        try
        {
            await for (final entity in dir.list(followLinks: false))
            {
                if (entity is Directory) return true;
            }
        }
        catch (_)
        {
            // 忽略
        }
        return false;
    }
}
