import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/library_album_model.dart';

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
            final jsonList = _albums.map((a) => _toJson(a)).toList();
            await file.writeAsString(jsonEncode(jsonList));
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
            'addedAt': album.addedAt,
            'lastReadAt': album.lastReadAt,
            'lastReadPage': album.lastReadPage,
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
            ..addedAt = json['addedAt']?.toString() ?? ''
            ..lastReadAt = json['lastReadAt']?.toString()
            ..lastReadPage = (json['lastReadPage'] as num?)?.toInt() ?? 0;
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
    Future<void> updateReadProgress(String albumId, int page) async
    {
        await _ensureLoaded();
        final album = _albums.where((a) => a.albumId == albumId).firstOrNull;
        if (album != null)
        {
            album.lastReadPage = page;
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

    /// 扫描下载目录（空实现）
    Future<void> syncFromDirectory(String downloadDir) async {}
}
