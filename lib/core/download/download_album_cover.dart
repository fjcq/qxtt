part of 'download_service.dart';

/// 负责整本下载的封面获取（从 download_album_handler.dart 拆出，
/// 控制单文件行数）
extension DownloadServiceAlbumCover on DownloadService
{
    /// 下载本子封面并保存为 cover.jpg
    ///
    /// 依次尝试 3x4/2x3/原始三种尺寸的封面 URL；
    /// 全部失败时回退复制第一章首图（[fallbackFirstImage]）
    Future<String> _downloadAlbumCover(
        String albumId,
        String savePath, {
        String fallbackFirstImage = '',
    }) async
    {
        // 确保封面所在目录存在（忽略失败：写文件时会再次暴露问题）
        try
        {
            final dir = File(savePath).parent;
            if (!await dir.exists())
            {
                await dir.create(recursive: true);
            }
        }
        catch (_)
        {
        }

        for (final size in const ['_3x4', '_2x3', ''])
        {
            final url = _client.getAlbumCoverUrl(albumId, size: size);
            if (await _fetchBytesToFile(url, savePath)) return savePath;
        }

        // 兜底：复制第一章首图作为封面
        if (fallbackFirstImage.isNotEmpty)
        {
            final src = File(fallbackFirstImage);
            if (await src.exists())
            {
                try
                {
                    await src.copy(savePath);
                    return savePath;
                }
                catch (_)
                {
                    return fallbackFirstImage;
                }
            }
        }
        return '';
    }

    /// 从 URL 拉取字节并写入文件
    Future<bool> _fetchBytesToFile(String url, String savePath) async
    {
        try
        {
            final resp = await _client.dio.get<List<int>>(
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
        }
        return false;
    }
}
