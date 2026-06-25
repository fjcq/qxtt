import 'dart:convert';
import 'dart:io';

import '../core/jm/jm_entity.dart';

/// 单章节的本地持久化元数据
/// 用于离线时重建章节页面列表与解密参数，避免阅读器启动时强制走网络
class ChapterMetadata
{
    /// 章节 ID
    final String photoId;

    /// 章节序号（与目录名一致）
    final String index;

    /// 章节名
    final String name;

    /// scramble_id（解密参数）
    final int scrambleId;

    /// 图片文件名列表（来自 PhotoDetail.pageArr）
    final List<String> pageArr;

    const ChapterMetadata({
        required this.photoId,
        required this.index,
        required this.name,
        required this.scrambleId,
        required this.pageArr,
    });

    /// 从 JSON 构造
    factory ChapterMetadata.fromJson(Map<String, dynamic> json)
    {
        return ChapterMetadata(
            photoId: json['photoId']?.toString() ?? '',
            index: json['index']?.toString() ?? '',
            name: json['name']?.toString() ?? '',
            scrambleId: (json['scrambleId'] as num?)?.toInt() ?? 0,
            pageArr: (json['pageArr'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [],
        );
    }

    /// 序列化为 JSON
    Map<String, dynamic> toJson()
    {
        return {
            'photoId': photoId,
            'index': index,
            'name': name,
            'scrambleId': scrambleId,
            'pageArr': pageArr,
        };
    }
}

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
    ///
    /// [chapters] 为可选的章节级扩展元数据（含 scrambleId + pageArr），
    /// 传入时会一并写入 `chapters` 字段，阅读器离线加载时可直接复用。
    static Future<void> saveAlbumMetadata(
        String albumDir,
        AlbumDetail albumDetail, {
        Map<String, ChapterMetadata>? chapters,
    }) async
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
            if (chapters != null && chapters.isNotEmpty)
            {
                json['chapters'] = chapters.map(
                    (key, value) => MapEntry(key, value.toJson()),
                );
            }
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
        final (detail, dirs, _) = await loadAlbumMetadataWithChapters(albumDir);
        return (detail, dirs);
    }

    /// 加载本子元数据（含章节级扩展元数据）
    /// 返回 (AlbumDetail?, photoId -> 章节目录, photoId -> 章节扩展元数据)
    static Future<(
        AlbumDetail?,
        Map<String, String>,
        Map<String, ChapterMetadata>
    )> loadAlbumMetadataWithChapters(String albumDir) async
    {
        final file = File(_getMetadataPath(albumDir));
        if (!await file.exists())
        {
            return (null, <String, String>{}, <String, ChapterMetadata>{});
        }

        try
        {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final episodesJson = json['episodes'] as List<dynamic>? ?? [];
            final episodes = <Episode>[];
            final dirs = <String, String>{};
            final chapters = <String, ChapterMetadata>{};

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

            // 解析扩展章节元数据（scrambleId + pageArr）
            final chaptersJson = json['chapters'] as Map<String, dynamic>?;
            if (chaptersJson != null)
            {
                chaptersJson.forEach((key, value)
                {
                    if (value is Map<String, dynamic>)
                    {
                        chapters[key] = ChapterMetadata.fromJson(value);
                    }
                });
            }

            final detail = AlbumDetail(
                albumId: json['albumId']?.toString() ?? '',
                name: json['name']?.toString() ?? '',
                author: json['author']?.toString() ?? '',
                pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
                episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
                episodes: episodes,
            );
            return (detail, dirs, chapters);
        }
        catch (_)
        {
            return (null, <String, String>{}, <String, ChapterMetadata>{});
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
            final (existing, _, chapters) =
                await loadAlbumMetadataWithChapters(albumDir);
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
            await saveAlbumMetadata(
                albumDir, detail,
                chapters: chapters,
            );
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 增量写入单章节的扩展元数据（scrambleId + pageArr）
    /// 下载完成时调用，阅读器离线加载时可直接复用避免网络请求
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
        try
        {
            final (existing, _, chapters) =
                await loadAlbumMetadataWithChapters(albumDir);
            final episodes = existing?.episodes.toList() ?? [];
            episodes.removeWhere((ep) => ep.photoId == photoId);
            episodes.add(Episode(
                photoId: photoId,
                index: index,
                name: name,
            ));
            episodes.sort((a, b) => a.index.compareTo(b.index));

            final newChapters = Map<String, ChapterMetadata>.from(chapters);
            newChapters[photoId] = ChapterMetadata(
                photoId: photoId,
                index: index,
                name: name,
                scrambleId: scrambleId,
                pageArr: List<String>.from(pageArr),
            );

            final detail = AlbumDetail(
                albumId: albumId ?? existing?.albumId ?? '',
                name: title ?? existing?.name ?? '',
                author: author ?? existing?.author ?? '',
                pageCount: existing?.pageCount ?? 0,
                episodeCount: existing?.episodeCount ?? 0,
                episodes: episodes,
            );
            await saveAlbumMetadata(
                albumDir, detail,
                chapters: newChapters,
            );
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }
}
