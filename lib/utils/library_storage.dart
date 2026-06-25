/// 已下载漫画的本地文件操作模块统一导出
/// 本文件作为 barrel file，并保留 [LibraryStorage] 外观类以兼容既有调用。
library library_storage;

import 'dart:io';

import '../core/jm/jm_entity.dart';
import '../data/models/library_album_model.dart';
import 'album_disk_stats.dart';
import 'album_disk_usage.dart';
import 'album_file_deleter.dart';
import 'album_force_delete.dart';
import 'album_metadata_storage.dart';
import 'album_path_resolver.dart';

export 'album_disk_stats.dart';
export 'album_disk_usage.dart';
export 'album_file_deleter.dart';
export 'album_force_delete.dart';
export 'album_metadata_storage.dart';
export 'album_path_resolver.dart';
export 'chapter_complete_helper.dart';

/// 已下载漫画的本地文件操作外观类
/// 负责：计算占用、清理文件、扫描本地目录、元数据管理
/// 实际实现已拆分到各子模块，本类仅做委托以保持既有 API 兼容。
class LibraryStorage
{
    LibraryStorage._();

    /// 获取应用下载根目录
    static Future<String> getDownloadDir({String configured = ''}) async
    {
        return AlbumPathResolver.getDownloadDir(configured: configured);
    }

    /// 保存本子元数据到本地目录
    static Future<void> saveAlbumMetadata(
        String albumDir,
        AlbumDetail albumDetail, {
        Map<String, ChapterMetadata>? chapters,
    }) async
    {
        return AlbumMetadataStorage.saveAlbumMetadata(
            albumDir, albumDetail, chapters: chapters,
        );
    }

    /// 加载本子元数据
    static Future<(AlbumDetail?, Map<String, String>)> loadAlbumMetadata(
        String albumDir,
    ) async
    {
        return AlbumMetadataStorage.loadAlbumMetadata(albumDir);
    }

    /// 加载本子元数据（含章节级扩展元数据：scrambleId + pageArr）
    static Future<(
        AlbumDetail?,
        Map<String, String>,
        Map<String, ChapterMetadata>
    )> loadAlbumMetadataWithChapters(String albumDir) async
    {
        return AlbumMetadataStorage.loadAlbumMetadataWithChapters(albumDir);
    }

    /// 将单章信息追加或更新到本子元数据
    static Future<void> updateAlbumMetadataWithEpisode(
        String albumDir, {
        required String photoId,
        required String index,
        String name = '',
        String? albumId,
        String? title,
        String? author,
    }) async
    {
        return AlbumMetadataStorage.updateAlbumMetadataWithEpisode(
            albumDir,
            photoId: photoId,
            index: index,
            name: name,
            albumId: albumId,
            title: title,
            author: author,
        );
    }

    /// 增量写入单章节的扩展元数据（scrambleId + pageArr）
    static Future<void> saveChapterMetadata(
        String albumDir, {
        required String photoId,
        required String index,
        required String name,
        required int scrambleId,
        required List<String> pageArr,
        String? albumId,
        String? title,
        String? author,
    }) async
    {
        return AlbumMetadataStorage.saveChapterMetadata(
            albumDir,
            photoId: photoId,
            index: index,
            name: name,
            scrambleId: scrambleId,
            pageArr: pageArr,
            albumId: albumId,
            title: title,
            author: author,
        );
    }

    /// 解析本子对应的实际本地根目录
    static Future<String> resolveAlbumDir(
        LibraryAlbumModel album, {
        required String downloadDir,
    }) async
    {
        return AlbumPathResolver.resolveAlbumDir(
            album, downloadDir: downloadDir,
        );
    }

    /// 计算指定目录的占用（字节 + 文件数）
    static Future<AlbumDiskStats> computeDiskUsage(String dirPath) async
    {
        return AlbumDiskUsage.computeDiskUsage(dirPath);
    }

    /// 批量计算多本漫画的本地占用
    static Future<Map<String, AlbumDiskStats>> computeBatchDiskUsage(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        return AlbumDiskUsage.computeBatchDiskUsage(
            albums, downloadDir: downloadDir,
        );
    }

    /// 删除单本漫画的本地文件（彻底删除）
    static Future<bool> deleteAlbumFiles(
        LibraryAlbumModel album, {
        required String downloadDir,
    }) async
    {
        return AlbumFileDeleter.deleteAlbumFiles(
            album, downloadDir: downloadDir,
        );
    }

    /// 强制删除目录：递归失败时多重兜底
    static Future<bool> forceDelete(
        Directory dir, {
        int maxRetries = 4,
    }) async
    {
        return AlbumForceDelete.forceDelete(dir, maxRetries: maxRetries);
    }

    /// 批量删除多本漫画的本地文件
    static Future<Map<String, bool>> deleteBatchAlbumFiles(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        return AlbumFileDeleter.deleteBatchAlbumFiles(
            albums, downloadDir: downloadDir,
        );
    }

    /// 删除下载根目录下的孤儿文件
    static Future<List<String>> cleanupOrphans(
        List<LibraryAlbumModel> albums, {
        required String downloadDir,
    }) async
    {
        return AlbumFileDeleter.cleanupOrphans(
            albums, downloadDir: downloadDir,
        );
    }

    /// 将字节数格式化为可读字符串（KB/MB/GB）
    static String formatSize(int bytes)
    {
        return AlbumDiskUsage.formatSize(bytes);
    }
}
