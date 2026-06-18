part of 'jm_client.dart';

/// JmClient 的图片下载层，负责：
///   - 单张图片二进制下载（带域名失败切换 + 域名刷新重试）
///   - 图片下载到文件（支持断点续传、进度回调）
class _JmImageDownloader extends _JmApiClient
{
    _JmImageDownloader({super.proxyUrl, super.useProxy});

    /// 下载图片二进制数据
    /// 仿照 Python 版 request_with_retry：先在当前域名上重试 N 次，
    /// 全部失败后自动切换到下一个域名，遍历所有图片域名。
    /// 使用 [ResponseType.stream] 流式消费确保数据完整。
    /// 当所有域名都失败时，会自动调用 [updateApiDomains] 刷新一次域名并再尝试一轮。
    Future<List<int>> downloadImage(String photoId, String filename,
        {CancelToken? cancelToken}) async
    {
        try
        {
            return await _downloadImageOnce(photoId, filename, cancelToken);
        }
        on Exception catch (e)
        {
            _log('image', '所有域名失败，准备强制刷新域名: '
                '$photoId/$filename, err=$e');
            try
            {
                await updateApiDomains(forceReload: true);
            }
            catch (updateErr)
            {
                _log('image', '域名更新失败: $updateErr');
            }
            return await _downloadImageOnce(photoId, filename, cancelToken,
                onRetryAfterDomainUpdate: true);
        }
    }

    /// 单轮下载（遍历 _imageDomainList 当前的快照，3 次重试/域名）
    Future<List<int>> _downloadImageOnce(
        String photoId,
        String filename,
        CancelToken? cancelToken, {
        bool onRetryAfterDomainUpdate = false,
    }) async
    {
        const maxRetries = 3;
        final domains = _imageDomainList.toList();
        if (onRetryAfterDomainUpdate)
        {
            _log('image', '使用刷新后域名重试: $photoId/$filename, '
                '${domains.length} 个域名');
        }
        Object? lastError;

        for (var i = 0; i < domains.length; i++)
        {
            final domain = domains[i];
            for (var attempt = 0; attempt < maxRetries; attempt++)
            {
                try
                {
                    final url = getImageUrlOnDomain(domain, photoId, filename);
                    final resp = await _dio.get<ResponseBody>(
                        url,
                        options: Options(
                            responseType: ResponseType.stream,
                            headers: {
                                ...JmConfig.appHeadersImage,
                            },
                        ),
                        cancelToken: cancelToken,
                    );
                    if (resp.data == null)
                    {
                        throw DioException(
                            requestOptions: RequestOptions(path: url),
                            message: '图片响应为空',
                        );
                    }

                    final builder = BytesBuilder(copy: false);
                    var received = 0;
                    await for (final chunk in resp.data!.stream)
                    {
                        builder.add(chunk);
                        received += chunk.length;
                    }
                    final bytes = builder.takeBytes();
                    if (bytes.isEmpty)
                    {
                        throw DioException(
                            requestOptions: RequestOptions(path: url),
                            message: '图片响应为空',
                        );
                    }

                    final contentLength = resp.headers.value(
                        HttpHeaders.contentLengthHeader,
                    );
                    if (contentLength != null)
                    {
                        final expected = int.tryParse(contentLength) ?? -1;
                        if (expected > 0 && expected != received)
                        {
                            // JM 服务器常对图片响应做 gzip / chunked 编码，
                            // Content-Length 与实际流式接收字节数可能不一致，
                            // 只要数据非空且 HTTP 成功即认为下载成功，不再强制校验长度。
                            _log('image', '图片长度差异(忽略): $photoId/$filename, '
                                '期望 $expected 字节, 实际 $received 字节, url=$url');
                        }
                    }
                    return bytes;
                }
                on DioException catch (e)
                {
                    lastError = e;
                    if (CancelToken.isCancel(e)) rethrow;
                    final code = e.response?.statusCode ?? 0;
                    if (code >= 400 && code < 500 && code != 408 && code != 429)
                    {
                        break;
                    }
                    if (attempt < maxRetries - 1)
                    {
                        await Future.delayed(
                            Duration(milliseconds: 300 * (attempt + 1)),
                        );
                    }
                }
            }
        }

        throw Exception('所有图片域名均失败: $photoId/$filename, 最后错误: $lastError');
    }

    /// 流式下载图片到文件，支持 HTTP Range 字节级断点续传
    /// - 若 [savePath] 已存在且非空，会先 HEAD 请求获取远程文件总大小；
    ///   若本地大小 < 远程大小，自动在请求中追加 `Range: bytes={localSize}-` 头
    ///   并以 append 模式打开文件继续写入。
    /// - 若本地大小 == 远程大小，认为已下载完成，方法立即返回 false 表示未发起下载。
    /// - [onProgress] 接收 (已接收字节, 总字节)。总字节在断点续传时为远程总大小。
    /// - 返回 true 表示本次确实发起了网络请求；false 表示文件已完整无需下载。
    /// - 当所有域名都失败时，会自动调用 [updateApiDomains] 刷新一次域名并再尝试一轮。
    Future<bool> downloadImageToFile(
        String photoId,
        String filename,
        String savePath, {
        CancelToken? cancelToken,
        void Function(int received, int total)? onProgress,
    }) async
    {
        try
        {
            return await _downloadImageToFileOnce(
                photoId, filename, savePath,
                cancelToken: cancelToken,
                onProgress: onProgress,
            );
        }
        on Exception catch (e)
        {
            _log('image', '所有域名失败(toFile)，准备强制刷新域名: '
                '$photoId/$filename, err=$e');
            try
            {
                await updateApiDomains(forceReload: true);
            }
            catch (updateErr)
            {
                _log('image', '域名更新失败: $updateErr');
            }
            return _downloadImageToFileOnce(
                photoId, filename, savePath,
                cancelToken: cancelToken,
                onProgress: onProgress,
                onRetryAfterDomainUpdate: true,
            );
        }
    }

    /// 单轮下载到文件
    Future<bool> _downloadImageToFileOnce(
        String photoId,
        String filename,
        String savePath, {
        CancelToken? cancelToken,
        void Function(int received, int total)? onProgress,
        bool onRetryAfterDomainUpdate = false,
    }) async
    {
        const maxRetries = 3;
        final domains = _imageDomainList.toList();
        if (onRetryAfterDomainUpdate)
        {
            _log('image', '使用刷新后域名重试(toFile): $photoId/$filename, '
                '${domains.length} 个域名');
        }
        Object? lastError;

        var localSize = 0;
        final localFile = File(savePath);
        if (localFile.existsSync())
        {
            localSize = localFile.lengthSync();
        }

        for (var i = 0; i < domains.length; i++)
        {
            final domain = domains[i];
            for (var attempt = 0; attempt < maxRetries; attempt++)
            {
                try
                {
                    final url = getImageUrlOnDomain(domain, photoId, filename);

                    var totalSize = localSize;
                    try
                    {
                        final headResp = await _dio.head<dynamic>(
                            url,
                            options: Options(
                                headers: {
                                    ...JmConfig.appHeadersImage,
                                },
                                followRedirects: true,
                                validateStatus: (status)
                                {
                                    return status != null && status < 500;
                                },
                            ),
                            cancelToken: cancelToken,
                        );
                        final contentLength =
                            headResp.headers.value(HttpHeaders.contentLengthHeader);
                        if (contentLength != null)
                        {
                            totalSize = int.tryParse(contentLength) ?? localSize;
                        }
                    }
                    on DioException
                    {
                        // HEAD 失败也不影响后续下载尝试
                    }

                    if (totalSize > 0 && localSize >= totalSize)
                    {
                        return false;
                    }

                    final headers = <String, dynamic>{
                        ...JmConfig.appHeadersImage,
                    };
                    if (localSize > 0)
                    {
                        headers['Range'] = 'bytes=$localSize-';
                    }

                    await _dio.download(
                        url,
                        savePath,
                        options: Options(
                            headers: headers,
                        ),
                        deleteOnError: false,
                        cancelToken: cancelToken,
                        onReceiveProgress: onProgress,
                    );

                    return true;
                }
                on DioException catch (e)
                {
                    lastError = e;
                    if (CancelToken.isCancel(e)) rethrow;
                    if (e.response?.statusCode == 416)
                    {
                        if (localFile.existsSync())
                        {
                            try
                            {
                                await localFile.delete();
                            }
                            catch (_)
                            {
                            }
                        }
                        localSize = 0;
                    }
                    final code = e.response?.statusCode ?? 0;
                    if (code >= 400 && code < 500 && code != 408 && code != 429 && code != 416)
                    {
                        break;
                    }
                    if (attempt < maxRetries - 1)
                    {
                        await Future.delayed(
                            Duration(milliseconds: 300 * (attempt + 1)),
                        );
                    }
                }
            }
        }

        throw Exception('所有图片域名均失败: $photoId/$filename, 最后错误: $lastError');
    }
}
