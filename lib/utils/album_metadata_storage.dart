import 'dart:convert';
import 'dart:io';

import '../core/jm/jm_entity.dart';

/// 本子元数据读写工具
/// 用于离线时重建章节列表与本地路径映射
class AlbumMetadataStorage
{
    AlbumMetadataStorage._();

    /// 获取本子元数据文件路径
    static String _getMetadataPath(String albumDir)
    {
        return '$albumDir${Platform.pathSeparator}.jm_album_meta.json';
    }

    /// 保存本子元数据到本地目录
    static Future<void> saveAlbumMetadata(
        String albumDir,
        AlbumDetail albumDetail,
    ) async
    {
        try
        {
            final file = File(_getMetadataPath(albumDir));
            await file.parent.create(recursive: true);
            final episodes = albumDetail.episodes.map((ep)
            {
                return {
                    'photoId': ep.photoId,
                    'index': ep.index,
                    'name': ep.name,
                };
            }).toList();
            final json = <String, dynamic>{
                'albumId': albumDetail.albumId,
                'name': albumDetail.name,
                'author': albumDetail.author,
                'pageCount': albumDetail.pageCount,
                'episodeCount': albumDetail.episodeCount,
                'episodes': episodes,
            };
            await file.writeAsString(jsonEncode(json), flush: true);
        }
        catch (_)
        {
            // 元数据写入失败不应阻塞下载主流程
        }
    }

    /// 加载本子元数据
    /// 返回 (重建的 AlbumDetail?, photoId -> 本地章节目录的映射)
    static Future<(AlbumDetail?, Map<String, String>)> loadAlbumMetadata(
        String albumDir,
    ) async
    {
        final file = File(_getMetadataPath(albumDir));
        if (!await file.exists()) return (null, <String, String>{});

        try
        {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final episodesJson = json['episodes'] as List<dynamic>? ?? [];
            final episodes = <Episode>[];
            final dirs = <String, String>{};

            for (final raw in episodesJson)
            {
                final e = raw as Map<String, dynamic>;
                final photoId = e['photoId']?.toString() ?? '';
                final index = e['index']?.toString() ?? '';
                final name = e['name']?.toString() ?? '';
                if (photoId.isEmpty || index.isEmpty) continue;

                episodes.add(Episode(
                    photoId: photoId,
                    index: index,
                    name: name,
                ));
                dirs[photoId] = '$albumDir${Platform.pathSeparator}$index';
            }

            final detail = AlbumDetail(
                albumId: json['albumId']?.toString() ?? '',
                name: json['name']?.toString() ?? '',
                author: json['author']?.toString() ?? '',
                pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
                episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
                episodes: episodes,
            );
            return (detail, dirs);
        }
        catch (_)
        {
            return (null, <String, String>{});
        }
    }

    /// 将单章信息追加或更新到本子元数据
    /// 适用于单章下载场景：多次下载同一本子的不同章节时，
    /// 逐步完善本地元数据，使离线重建章节列表更准确
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
        try
        {
            final (existing, _) = await loadAlbumMetadata(albumDir);
            final episodes = existing?.episodes.toList() ?? [];
            episodes.removeWhere((ep) => ep.photoId == photoId);
            episodes.add(Episode(
                photoId: photoId,
                index: index,
                name: name,
            ));
            episodes.sort((a, b) => a.index.compareTo(b.index));

            final detail = AlbumDetail(
                albumId: albumId ?? existing?.albumId ?? '',
                name: title ?? existing?.name ?? '',
                author: author ?? existing?.author ?? '',
                pageCount: existing?.pageCount ?? 0,
                episodeCount: existing?.episodeCount ?? 0,
                episodes: episodes,
            );
            await saveAlbumMetadata(albumDir, detail);
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }
}
