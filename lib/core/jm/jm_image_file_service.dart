import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'jm_config.dart';

/// 禁漫自定义图片文件服务
/// 添加默认请求头和重试逻辑，解决并发图片加载失败问题
class JmImageFileService extends FileService
{
    /// 最大并发下载数
    @override
    int get concurrentFetches => 5;

    /// 最大重试次数
    static const int _maxRetries = 3;

    /// 重试间隔（毫秒）
    static const int _retryDelayMs = 500;

    /// 代理地址（例如 "127.0.0.1:7890"），null 表示不用代理
    final String? proxyUrl;

    final http.Client _httpClient;

    /// 提供当前图片域名列表的回调
    /// 传入 null 时使用 JmConfig.domainImageList 的硬编码兜底列表
    final List<String> Function()? _imageDomainProvider;

    JmImageFileService({
        this.proxyUrl,
        http.Client? httpClient,
        List<String> Function()? imageDomainProvider,
    })  : _httpClient = httpClient ?? _buildHttpClient(proxyUrl),
          _imageDomainProvider = imageDomainProvider;

    /// 构造带代理的 http.Client
    static http.Client _buildHttpClient(String? proxyUrl)
    {
        if (proxyUrl == null || proxyUrl.isEmpty)
        {
            return http.Client();
        }
        return IOClient(HttpClient()..findProxy = (uri) => 'PROXY $proxyUrl');
    }

    @override
    Future<FileServiceResponse> get(String url,
        {Map<String, String>? headers}) async
    {
        // 合并默认请求头和自定义请求头
        final mergedHeaders = <String, String>{
            'Accept': JmConfig.appHeadersImage['Accept']!,
            'X-Requested-With': JmConfig.appHeadersImage['X-Requested-With']!,
            'Referer': JmConfig.appHeadersImage['Referer']!,
            'User-Agent': JmConfig.appHeadersTemplate['User-Agent']!,
        };
        if (headers != null)
        {
            mergedHeaders.addAll(headers);
        }

        // 域名降级重试：从原 URL 中提取 photoId/filename/albumId，
        // 在所有图片域名上依次尝试
        final candidates = _buildCandidateUrls(url);
        Object? lastError;

        for (final candidateUrl in candidates)
        {
            for (var attempt = 0; attempt < _maxRetries; attempt++)
            {
                try
                {
                    final req = http.Request('GET', Uri.parse(candidateUrl));
                    req.headers.addAll(mergedHeaders);
                    final httpResponse = await _httpClient.send(req);

                    // 成功响应
                    if (httpResponse.statusCode >= 200 &&
                        httpResponse.statusCode < 300)
                    {
                        return HttpGetResponse(httpResponse);
                    }

                    // 4xx（除 408/429）直接换域名，不在当前域名上重试
                    if (httpResponse.statusCode >= 400 &&
                        httpResponse.statusCode < 500 &&
                        httpResponse.statusCode != 408 &&
                        httpResponse.statusCode != 429)
                    {
                        lastError = Exception(
                            'HTTP ${httpResponse.statusCode}: $candidateUrl',
                        );
                        await httpResponse.stream.drain();
                        break;
                    }

                    // 5xx / 网络错误 → 当前域名上重试
                    await httpResponse.stream.drain();
                    lastError = Exception(
                        'HTTP ${httpResponse.statusCode}: $candidateUrl',
                    );
                    if (attempt < _maxRetries - 1)
                    {
                        await Future.delayed(
                            Duration(milliseconds: _retryDelayMs * (attempt + 1)),
                        );
                    }
                }
                on Exception catch (e)
                {
                    lastError = e;
                    if (attempt < _maxRetries - 1)
                    {
                        await Future.delayed(
                            Duration(milliseconds: _retryDelayMs * (attempt + 1)),
                        );
                    }
                }
            }
        }

        throw Exception('所有图片域名均失败, 最后错误: $lastError');
    }

    /// 构造所有候选 URL（同一资源在不同图片域名上的 URL 列表）
    /// 识别两类路径:
    /// 1. /media/photos/{photoId}/{filename} → 章节图片
    /// 2. /media/albums/{albumId}{size}.jpg → 封面
    static final RegExp _photoPathRe = RegExp(r'/media/photos/([^/]+)/(.+)$');
    static final RegExp _albumPathRe = RegExp(r'/media/albums/(.+)$');

    /// 获取当前生效的图片域名列表
    /// 优先使用外部注入的 provider（保证跟随 JmClient 的自动更新），
    /// 兜底使用 JmConfig 硬编码列表
    List<String> _currentImageDomains()
    {
        final list = _imageDomainProvider?.call();
        if (list != null && list.isNotEmpty)
        {
            return list;
        }
        return JmConfig.domainImageList;
    }

    List<String> _buildCandidateUrls(String originalUrl)
    {
        try
        {
            final uri = Uri.parse(originalUrl);
            final path = uri.path;
            final candidates = <String>[];
            final imageDomains = _currentImageDomains();

            final photoMatch = _photoPathRe.firstMatch(path);
            if (photoMatch != null)
            {
                final photoId = photoMatch.group(1)!;
                final filename = photoMatch.group(2)!;
                for (final domain in imageDomains)
                {
                    candidates.add(
                        'https://$domain/media/photos/$photoId/$filename',
                    );
                }
                return candidates;
            }

            final albumMatch = _albumPathRe.firstMatch(path);
            if (albumMatch != null)
            {
                final tail = albumMatch.group(1)!;
                for (final domain in imageDomains)
                {
                    candidates.add('https://$domain/media/albums/$tail');
                }
                return candidates;
            }

            // 非 jm 资源：只返回原 URL
            return [originalUrl];
        }
        catch (_)
        {
            return [originalUrl];
        }
    }
}
