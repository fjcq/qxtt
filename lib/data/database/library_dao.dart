import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/library_album_model.dart';

/// 单本漫画的本地占用统计
/// 供 [LibraryDao.updateAlbumsSize] 批量写入使用
class AlbumSizeStats
{
    /// 占用的字节数
    final int sizeBytes;

    /// 文件数
    final int fileCount;

    const AlbumSizeStats({required this.sizeBytes, required this.fileCount});
}

/// 书架数据访问对象（每本子一个 JSON 文件 + 索引文件）
///
/// 【性能优化 P2 - 路线图第三阶段】
/// 旧实现：所有本子序列化为单个 `library_albums.json` 文件，
/// 每次更新单个本子都要全量重写整个文件，O(N) 写入开销。
///
/// 新实现：
/// - `library_index.json`：轻量索引，仅存 albumId 列表
/// - `library_albums/{albumId}.json`：单个本子的完整数据
/// - 更新单个本子只写该本子文件，O(1) 写入开销
/// - 索引仅在 add/remove 时更新
///
/// 数据迁移：首次启动检测旧 `library_albums.json`，自动拆分迁移到新结构
class LibraryDao
{
    List<LibraryAlbumModel> _albums = [];
    final Set<String> _albumIds = {};
    bool _loaded = false;

    /// 获取旧版全量文件路径（用于迁移检测）
    Future<String> _getLegacyFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}library_albums.json';
    }

    /// 获取本子数据存储目录
    Future<String> _getAlbumsDir() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}library_albums';
    }

    /// 获取索引文件路径
    Future<String> _getIndexPath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}library_index.json';
    }

    /// 获取单个本子文件路径
    /// albumId 可能含特殊字符，做 sanitize 避免文件系统错误
    Future<String> _getAlbumFilePath(String albumId) async
    {
        final albumsDir = await _getAlbumsDir();
        final safeId = _sanitizeAlbumId(albumId);
        return '$albumsDir${Platform.pathSeparator}$safeId.json';
    }

    /// 替换 Windows 文件系统不允许的字符为下划线
    String _sanitizeAlbumId(String albumId)
    {
        return albumId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }

    /// 确保数据已从文件加载（含旧版迁移）
    Future<void> _ensureLoaded() async
    {
        if (_loaded) return;
        _loaded = true;

        try
        {
            // 1. 旧版数据迁移
            await _migrateLegacyIfNeeded();

            // 2. 加载索引
            final indexFile = File(await _getIndexPath());
            if (await indexFile.exists())
            {
                final content = await indexFile.readAsString();
                final jsonList = jsonDecode(content) as List<dynamic>;
                _albumIds.clear();
                for (final e in jsonList)
                {
                    _albumIds.add(e.toString());
                }
            }

            // 3. 加载所有本子文件
            _albums = [];
            for (final albumId in _albumIds)
            {
                final album = await _loadAlbumFile(albumId);
                if (album != null)
                {
                    _albums.add(album);
                }
            }

            // 4. 索引与实际文件不一致时修正索引
            if (_albums.length != _albumIds.length)
            {
                _albumIds.clear();
                _albumIds.addAll(_albums.map((a) => a.albumId));
                await _saveIndex();
            }
        }
        catch (_)
        {
            _albums = [];
        }
    }

    /// 旧版全量文件迁移到每本子一个文件的结构
    Future<void> _migrateLegacyIfNeeded() async
    {
        try
        {
            final legacyFile = File(await _getLegacyFilePath());
            if (!await legacyFile.exists()) return;

            final indexFile = File(await _getIndexPath());
            // 索引已存在说明已迁移过，跳过
            if (await indexFile.exists()) return;

            // 读取旧版全量文件
            final content = await legacyFile.readAsString();
            final jsonList = jsonDecode(content) as List<dynamic>;
            final albums = jsonList
                .map((e) => _fromJson(e as Map<String, dynamic>))
                .toList();

            // 创建本子目录
            final albumsDir = Directory(await _getAlbumsDir());
            await albumsDir.create(recursive: true);

            // 写入每个本子单独文件
            final ids = <String>[];
            for (final album in albums)
            {
                await _writeAlbumFile(album);
                ids.add(album.albumId);
            }

            // 写入索引
            await indexFile.parent.create(recursive: true);
            await indexFile.writeAsString(jsonEncode(ids), flush: true);

            // 删除旧版文件
            await legacyFile.delete();
        }
        catch (_)
        {
            // 迁移失败不阻塞应用启动，下次启动会重试
        }
    }

    /// 加载单个本子文件
    Future<LibraryAlbumModel?> _loadAlbumFile(String albumId) async
    {
        try
        {
            final file = File(await _getAlbumFilePath(albumId));
            if (!await file.exists()) return null;
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            return _fromJson(json);
        }
        catch (_)
        {
            return null;
        }
    }

    /// 写入单个本子文件（增量保存核心）
    Future<void> _writeAlbumFile(LibraryAlbumModel album) async
    {
        try
        {
            final file = File(await _getAlbumFilePath(album.albumId));
            await file.parent.create(recursive: true);
            await file.writeAsString(
                jsonEncode(_toJson(album)), flush: true,
            );
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 删除单个本子文件
    Future<void> _deleteAlbumFile(String albumId) async
    {
        try
        {
            final file = File(await _getAlbumFilePath(albumId));
            if (await file.exists())
            {
                await file.delete();
            }
        }
        catch (_)
        {
            // 忽略删除失败
        }
    }

    /// 保存索引文件
    Future<void> _saveIndex() async
    {
        try
        {
            final file = File(await _getIndexPath());
            await file.parent.create(recursive: true);
            await file.writeAsString(
                jsonEncode(_albumIds.toList()), flush: true,
            );
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 增量保存：只写单个本子文件（不动索引）
    Future<void> _saveAlbum(LibraryAlbumModel album) async
    {
        await _writeAlbumFile(album);
    }

    /// 模型转JSON
    Map<String, dynamic> _toJson(LibraryAlbumModel album)
    {
        return {
            'albumId': album.albumId,
            'title': album.title,
            'author': album.author,
            'coverPath': album.coverPath,
            'localPath': album.localPath,
            'pageCount': album.pageCount,
            'episodeCount': album.episodeCount,
            'downloadedEpisodes': album.downloadedEpisodes,
            'addedAt': album.addedAt,
            'lastReadAt': album.lastReadAt,
            'lastReadPage': album.lastReadPage,
            'lastReadPhotoId': album.lastReadPhotoId,
            'sizeBytes': album.sizeBytes,
            'fileCount': album.fileCount,
        };
    }

    /// JSON转模型
    LibraryAlbumModel _fromJson(Map<String, dynamic> json)
    {
        return LibraryAlbumModel()
            ..albumId = json['albumId']?.toString() ?? ''
            ..title = json['title']?.toString() ?? ''
            ..author = json['author']?.toString() ?? ''
            ..coverPath = json['coverPath']?.toString() ?? ''
            ..localPath = json['localPath']?.toString() ?? ''
            ..pageCount = (json['pageCount'] as num?)?.toInt() ?? 0
            ..episodeCount = (json['episodeCount'] as num?)?.toInt() ?? 0
            ..downloadedEpisodes = (json['downloadedEpisodes'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[]
            ..addedAt = json['addedAt']?.toString() ?? ''
            ..lastReadAt = json['lastReadAt']?.toString()
            ..lastReadPage = (json['lastReadPage'] as num?)?.toInt() ?? 0
            ..lastReadPhotoId = json['lastReadPhotoId']?.toString() ?? ''
            ..sizeBytes = (json['sizeBytes'] as num?)?.toInt() ?? 0
            ..fileCount = (json['fileCount'] as num?)?.toInt() ?? 0;
    }

    /// 添加书架项
    Future<void> addAlbum(LibraryAlbumModel album) async
    {
        await _ensureLoaded();
        _albums.insert(0, album);
        final isNew = _albumIds.add(album.albumId);
        await _saveAlbum(album);
        if (isNew)
        {
            await _saveIndex();
        }
    }

    /// 获取所有书架项
    Future<List<LibraryAlbumModel>> getAllAlbums() async
    {
        await _ensureLoaded();
        return List.from(_albums);
    }

    /// 根据 albumId 查找
    Future<LibraryAlbumModel?> getByAlbumId(String albumId) async
    {
        await _ensureLoaded();
        return _albums.where((a) => a.albumId == albumId).firstOrNull;
    }

    /// 根据 photoId（章节 ID）查找所属本子
    /// 阅读器入口优先调用此方法，避免 `getAllAlbums` 全量复制 + 线性搜索
    Future<LibraryAlbumModel?> getAlbumByPhotoId(String photoId) async
    {
        await _ensureLoaded();
        for (final album in _albums)
        {
            if (album.downloadedEpisodes.contains(photoId)) return album;
        }
        return null;
    }

    /// 更新阅读进度（增量保存，只写单个本子）
    Future<void> updateReadProgress(
        String albumId,
        int page, {
        String? photoId,
    }) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album != null)
        {
            album.lastReadPage = page;
            if (photoId != null && photoId.isNotEmpty)
            {
                album.lastReadPhotoId = photoId;
            }
            album.lastReadAt = DateTime.now().toIso8601String();
            await _saveAlbum(album);
        }
    }

    /// 移除书架项
    Future<void> removeAlbum(String albumId) async
    {
        await _ensureLoaded();
        _albums.removeWhere((a) => a.albumId == albumId);
        final removed = _albumIds.remove(albumId);
        await _deleteAlbumFile(albumId);
        if (removed)
        {
            await _saveIndex();
        }
    }

    /// 批量移除书架项
    /// 一次移除多个 albumId，避免多次索引写入
    Future<void> removeAlbums(Iterable<String> albumIds) async
    {
        await _ensureLoaded();
        final idSet = albumIds.toSet();
        if (idSet.isEmpty) return;
        _albums.removeWhere((a) => idSet.contains(a.albumId));
        var indexChanged = false;
        for (final id in idSet)
        {
            await _deleteAlbumFile(id);
            if (_albumIds.remove(id))
            {
                indexChanged = true;
            }
        }
        if (indexChanged)
        {
            await _saveIndex();
        }
    }

    /// 更新指定 album 的本地占用统计（字节/文件数）
    /// 字段为 0 时不覆盖（保持已有值）
    Future<void> updateAlbumSize(
        String albumId, {
        int? sizeBytes,
        int? fileCount,
    }) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return;
        if (sizeBytes != null) album.sizeBytes = sizeBytes;
        if (fileCount != null) album.fileCount = fileCount;
        await _saveAlbum(album);
    }

    /// 一次性更新多个 album 的占用统计（增量保存每个本子）
    Future<void> updateAlbumsSize(Map<String, AlbumSizeStats> statsMap) async
    {
        await _ensureLoaded();
        if (statsMap.isEmpty) return;
        for (final entry in statsMap.entries)
        {
            final album = _albums.where((a) => a.albumId == entry.key).firstOrNull;
            if (album == null) continue;
            album.sizeBytes = entry.value.sizeBytes;
            album.fileCount = entry.value.fileCount;
            await _saveAlbum(album);
        }
    }

    /// 更新指定 album 的封面路径
    Future<void> updateAlbumCover(String albumId, String coverPath) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return;
        album.coverPath = coverPath;
        await _saveAlbum(album);
    }

    /// 清空整个书架
    Future<void> clearAll() async
    {
        await _ensureLoaded();
        final albumsDir = Directory(await _getAlbumsDir());
        if (await albumsDir.exists())
        {
            try
            {
                await albumsDir.delete(recursive: true);
            }
            catch (_)
            {
                // 忽略
            }
        }
        _albums = [];
        _albumIds.clear();
        await _saveIndex();
    }

    /// 扫描下载目录（空实现）
    Future<void> syncFromDirectory(String downloadDir) async {}

    /// 添加或更新书架项（按 albumId 唯一）
    Future<void> upsertAlbum(LibraryAlbumModel album) async
    {
        await _ensureLoaded();
        final existingIndex = _albums.indexWhere((a) => a.albumId == album.albumId);
        if (existingIndex >= 0)
        {
            // 已存在则合并已下载章节 ID
            final existing = _albums[existingIndex];
            final merged = <String>{
                ...existing.downloadedEpisodes,
                ...album.downloadedEpisodes,
            }.toList();
            existing
                ..title = album.title.isNotEmpty ? album.title : existing.title
                ..author = album.author.isNotEmpty ? album.author : existing.author
                ..coverPath = album.coverPath.isNotEmpty ? album.coverPath : existing.coverPath
                ..localPath = album.localPath.isNotEmpty ? album.localPath : existing.localPath
                ..pageCount = album.pageCount > 0 ? album.pageCount : existing.pageCount
                ..episodeCount = album.episodeCount > 0 ? album.episodeCount : existing.episodeCount
                ..downloadedEpisodes = merged;
            await _saveAlbum(existing);
        }
        else
        {
            _albums.insert(0, album);
            _albumIds.add(album.albumId);
            await _saveAlbum(album);
            await _saveIndex();
        }
    }

    /// 将指定章节标记为已下载
    /// 若书架中无该本子，则自动创建一个最小条目
    Future<void> markEpisodesDownloaded(
        String albumId,
        Iterable<String> photoIds, {
        String? title,
        String? author,
        String? coverPath,
        String? localPath,
        int? pageCount,
        int? episodeCount,
    }) async
    {
        await _ensureLoaded();
        final ids = photoIds.toSet();
        if (ids.isEmpty) return;

        final existingIndex = _albums.indexWhere((a) => a.albumId == albumId);
        if (existingIndex >= 0)
        {
            final existing = _albums[existingIndex];
            final merged = <String>{
                ...existing.downloadedEpisodes,
                ...ids,
            }.toList();
            existing
                ..title = (title != null && title.isNotEmpty) ? title : existing.title
                ..author = (author != null && author.isNotEmpty) ? author : existing.author
                ..coverPath = (coverPath != null && coverPath.isNotEmpty) ? coverPath : existing.coverPath
                ..localPath = (localPath != null && localPath.isNotEmpty) ? localPath : existing.localPath
                ..pageCount = (pageCount != null && pageCount > 0) ? pageCount : existing.pageCount
                ..episodeCount = (episodeCount != null && episodeCount > 0) ? episodeCount : existing.episodeCount
                ..downloadedEpisodes = merged;
            await _saveAlbum(existing);
        }
        else
        {
            final album = LibraryAlbumModel()
                ..albumId = albumId
                ..title = title ?? ''
                ..author = author ?? ''
                ..coverPath = coverPath ?? ''
                ..localPath = localPath ?? ''
                ..pageCount = pageCount ?? 0
                ..episodeCount = episodeCount ?? 0
                ..downloadedEpisodes = ids.toList()
                ..addedAt = DateTime.now().toIso8601String()
                ..lastReadPage = 0;
            _albums.insert(0, album);
            _albumIds.add(album.albumId);
            await _saveAlbum(album);
            await _saveIndex();
        }
    }

    /// 从已下载列表中移除指定章节
    /// 当本子没有任何已下载章节时，自动移除该书架项
    Future<void> removeDownloadedEpisodes(String albumId, Iterable<String> photoIds) async
    {
        await _ensureLoaded();
        final ids = photoIds.toSet();
        if (ids.isEmpty) return;

        final index = _albums.indexWhere((a) => a.albumId == albumId);
        if (index < 0) return;

        final album = _albums[index];
        album.downloadedEpisodes =
            album.downloadedEpisodes.where((e) => !ids.contains(e)).toList();

        if (album.downloadedEpisodes.isEmpty)
        {
            _albums.removeAt(index);
            _albumIds.remove(albumId);
            await _deleteAlbumFile(albumId);
            await _saveIndex();
        }
        else
        {
            await _saveAlbum(album);
        }
    }

    /// 获取指定本子的已下载章节 ID 集合
    Future<Set<String>> getDownloadedEpisodes(String albumId) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return <String>{};
        return album.downloadedEpisodes.toSet();
    }
}
