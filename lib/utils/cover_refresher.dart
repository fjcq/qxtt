import 'dart:io';

import 'package:dio/dio.dart';

import '../core/jm/jm_client.dart';
import '../data/models/library_album_model.dart';

/// 漫画封面补齐工具
/// 用于为本地已下载但缺封面的本子拉取并保存封面
class CoverRefresher
{
    final JmClient _client;
    final Dio _dio;

    CoverRefresher(this._client) : _dio = _client.dio;

    /// 为单个 album 补封面
    /// - coverPath 存在 → 跳过
    /// - 本地已有 cover.jpg → 仅回填 coverPath
    /// - 否则从远端拉取；失败时回退到本子首张已下载图
    /// 返回最终 coverPath；空表示补封面失败
    Future<String> refresh(LibraryAlbumModel album) async
    {
        // 已有 cover 且文件存在
        if (album.coverPath.isNotEmpty && File(album.coverPath).existsSync())
        {
            return album.coverPath;
        }

        final albumDir = _resolveAlbumDir(album);
        if (albumDir == null) return '';

        // 本地已有 cover.jpg 直接使用
        final localCover = File('$albumDir${Platform.pathSeparator}cover.jpg');
        if (await localCover.exists())
        {
            return localCover.path;
        }

        // 从远端拉取（依次尝试 _3x4 / _2x3 / 原始大小）
        for (final size in const ['_3x4', '_2x3', ''])
        {
            final url = _client.getAlbumCoverUrl(album.albumId, size: size);
            if (await _fetchTo(url, localCover.path)) return localCover.path;
        }

        // 拉取失败 → 用本子首张已下载图兜底
        final firstImg = await _findFirstImage(albumDir);
        if (firstImg != null) return firstImg;

        return '';
    }

    /// 计算本子目录（按 localPath → title 兜底）
    String? _resolveAlbumDir(LibraryAlbumModel album)
    {
        if (album.localPath.isNotEmpty) return album.localPath;
        if (album.title.isEmpty) return null;
        return null; // 默认下载根目录由 getDownloadDir 决定，但此处不依赖具体根
    }

    /// 实际下载到 savePath
    Future<bool> _fetchTo(String url, String savePath) async
    {
        try
        {
            final dir = File(savePath).parent;
            if (!await dir.exists()) await dir.create(recursive: true);
            final resp = await _dio.get<List<int>>(
                url,
                options: Options(
                    responseType: ResponseType.bytes,
                    receiveTimeout: const Duration(seconds: 15),
                    sendTimeout: const Duration(seconds: 10),
                ),
            );
            final code = resp.statusCode ?? 0;
            final data = resp.data;
            if (code >= 200 && code < 300 && data != null && data.isNotEmpty)
            {
                await File(savePath).writeAsBytes(data, flush: true);
                return true;
            }
        }
        catch (_)
        {
            // ignore
        }
        return false;
    }

    /// 找本子目录内第一张可用图片
    /// 配合 libraryDir 一起使用，因为 albumDir 解析需要下载根目录
    Future<String?> _findFirstImage(String albumDir) async
    {
        try
        {
            final dir = Directory(albumDir);
            if (!await dir.exists()) return null;
            final entries = await dir.list(recursive: true).toList();
            final images = entries
                .whereType<File>()
                .where((f) =>
                    f.path.toLowerCase().endsWith('.jpg') ||
                    f.path.toLowerCase().endsWith('.jpeg') ||
                    f.path.toLowerCase().endsWith('.webp') ||
                    f.path.toLowerCase().endsWith('.png'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
            return images.isEmpty ? null : images.first.path;
        }
        catch (_)
        {
            return null;
        }
    }
}
