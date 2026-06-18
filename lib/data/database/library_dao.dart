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

/// 书架数据访问对象（JSON文件持久化）
class LibraryDao
{
    List<LibraryAlbumModel> _albums = [];
    bool _loaded = false;

    /// 获取存储文件路径
    Future<String> _getFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}library_albums.json';
    }

    /// 确保数据已从文件加载
    Future<void> _ensureLoaded() async
    {
        if (_loaded) return;
        _loaded = true;

        try
        {
            final file = File(await _getFilePath());
            if (await file.exists())
            {
                final content = await file.readAsString();
                final jsonList = jsonDecode(content) as List<dynamic>;
                _albums = jsonList.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
            }
        }
        catch (_)
        {
            _albums = [];
        }
    }

    /// 保存数据到文件
    Future<void> _save() async
    {
        try
        {
            final file = File(await _getFilePath());
            // 显式创建父目录，避免在 Windows 首次运行时因
            // getApplicationSupportDirectory 返回的子目录尚未创建而写入失败
            await file.parent.create(recursive: true);
            final jsonList = _albums.map((a) => _toJson(a)).toList();
            await file.writeAsString(jsonEncode(jsonList), flush: true);
        }
        catch (_)
        {
            // 忽略写入失败
        }
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
        await _save();
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

    /// 更新阅读进度
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
            await _save();
        }
    }

    /// 移除书架项
    Future<void> removeAlbum(String albumId) async
    {
        await _ensureLoaded();
        _albums.removeWhere((a) => a.albumId == albumId);
        await _save();
    }

    /// 批量移除书架项
    /// 一次移除多个 albumId，避免多次 _save() 带来的 IO 开销
    Future<void> removeAlbums(Iterable<String> albumIds) async
    {
        await _ensureLoaded();
        final idSet = albumIds.toSet();
        if (idSet.isEmpty) return;
        _albums.removeWhere((a) => idSet.contains(a.albumId));
        await _save();
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
        await _save();
    }

    /// 一次性更新多个 album 的占用统计
    /// 传入 albumId -> 统计 的映射
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
        }
        await _save();
    }

    /// 更新指定 album 的封面路径
    /// 用于在远端拉取封面或本子首张图兜底后回填
    Future<void> updateAlbumCover(String albumId, String coverPath) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album == null) return;
        album.coverPath = coverPath;
        await _save();
    }

    /// 清空整个书架
    Future<void> clearAll() async
    {
        await _ensureLoaded();
        _albums = [];
        await _save();
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
        }
        else
        {
            _albums.insert(0, album);
        }
        await _save();
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
        }
        await _save();
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
        }
        await _save();
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
