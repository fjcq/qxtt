import 'dart:convert';

import 'package:dio/dio.dart';

import 'jm_config.dart';
import 'jm_crypto.dart';
import 'jm_entity.dart';

/// 禁漫 API 客户端
class JmClient
{
    late final Dio _dio;
    List<String> _domainList = List.from(JmConfig.domainApiList);
    List<String> _imageDomainList = List.from(JmConfig.domainImageList);
    Map<String, String> _cookies = {};
    int _retryTimes = 3;
    bool _initialized = false;

    JmClient()
    {
        _dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: Map<String, dynamic>.from(JmConfig.appHeadersTemplate),
        ));

        // 添加拦截器：自动携带 cookies
        _dio.interceptors.add(InterceptorsWrapper(
            onRequest: (options, handler)
            {
                if (_cookies.isNotEmpty)
                {
                    final cookieStr = _cookies.entries
                        .map((e) => '${e.key}=${e.value}')
                        .join('; ');
                    options.headers['Cookie'] = cookieStr;
                }
                handler.next(options);
            },
        ));
    }

    /// 确保初始化完成（更新域名 + 获取 cookies）
    Future<void> _ensureInitialized() async
    {
        if (_initialized) return;
        _initialized = true;

        try
        {
            // 先更新域名
            await updateApiDomains();
        }
        catch (_)
        {
            // 域名更新失败，使用默认域名
        }

        try
        {
            // 再获取 cookies
            await ensureCookies();
        }
        catch (_)
        {
            // cookies 获取失败，继续使用
        }
    }

    /// 获取当前 API 域名列表
    List<String> get domainList => _domainList;

    /// 获取当前图片域名列表
    List<String> get imageDomainList => _imageDomainList;

    /// 获取 Cookies
    Map<String, String> get cookies => _cookies;

    /// 获取 Dio 实例
    Dio get dio => _dio;

    /// 搜索漫画
    /// GET {domain}/search?search_query={}&page={}&main_tag={}&o={}&t={}
    Future<SearchResult> search(
        String query, {
        int page = 1,
        String searchType = 'site',
        String orderBy = 'mr',
        String time = 'a',
    }) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        // main_tag: 0=站内搜索, 1=标签搜索
        final mainTag = searchType == 'tag' ? 1 : 0;

        // 构建 o 参数
        final o = time == 'a' ? orderBy : '${orderBy}_$time';

        final resp = await _getWithDomainFallback(
            '/search',
            queryParameters: {
                'search_query': query,
                'page': page,
                'main_tag': mainTag,
                'o': o,
                't': time,
            },
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        final data = _decryptResponse(resp.data, ts);
        return SearchResult.fromJson(jsonDecode(data));
    }

    /// 获取本子详情
    /// GET {domain}/album?id={album_id}
    Future<AlbumDetail> getAlbumDetail(String albumId) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        final resp = await _getWithDomainFallback(
            '/album',
            queryParameters: {'id': albumId},
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        final data = _decryptResponse(resp.data, ts);
        return AlbumDetail.fromJson(jsonDecode(data));
    }

    /// 获取章节详情
    /// GET {domain}/chapter?id={photo_id}
    Future<PhotoDetail> getPhotoDetail(String photoId) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        final resp = await _getWithDomainFallback(
            '/chapter',
            queryParameters: {'id': photoId},
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        final data = _decryptResponse(resp.data, ts);
        return PhotoDetail.fromJson(jsonDecode(data));
    }

    /// 获取 scramble_id
    /// GET {domain}/chapter_view_template?id={photo_id}&mode=vertical&page=0
    /// 注意: 此接口使用 APP_TOKEN_SECRET_2
    Future<int> getScrambleId(String photoId) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateChapterViewToken(ts);

        final resp = await _getWithDomainFallback(
            '/chapter_view_template',
            queryParameters: {
                'id': photoId,
                'mode': 'vertical',
                'page': 0,
                'app_img_shunt': 1,
                'express': 'off',
                'v': ts,
            },
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        // 从 HTML 中正则匹配 var scramble_id = (\d+);
        final html = resp.data.toString();
        final match = RegExp(r'var\s+scramble_id\s*=\s*(\d+)').firstMatch(html);
        if (match != null)
        {
            return int.parse(match.group(1)!);
        }
        return 0;
    }

    /// 分类浏览
    /// GET {domain}/categories/filter?page={}&c={}&o={}&order={}
    /// o 参数格式: 排序方式(如 mr=最新, mv=最多观看) 或 排序_时间(如 mv_m=本月最多观看)
    Future<SearchResult> categoriesFilter({
        int page = 1,
        String category = '0',
        String orderBy = 'mr',
        String time = 'a',
    }) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        // 构建 o 参数: time='a' 时为 orderBy，否则为 orderBy_time
        final o = time == 'a' ? orderBy : '${orderBy}_$time';

        final resp = await _getWithDomainFallback(
            '/categories/filter',
            queryParameters: {
                'page': page,
                'order': '',
                'c': category,
                'o': o,
            },
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        final data = _decryptResponse(resp.data, ts);
        return SearchResult.fromJson(jsonDecode(data));
    }

    /// 登录
    /// POST {domain}/login
    Future<LoginResult> login(String username, String password) async
    {
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        final resp = await _dio.post(
            'https://${_domainList.first}/login',
            data: 'username=$username&password=$password',
            options: Options(
                headers: {
                    'token': token,
                    'tokenparam': tokenparam,
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
            ),
        );

        // 保存 cookies
        final setCookies = resp.headers['set-cookie'];
        if (setCookies != null)
        {
            for (final cookie in setCookies)
            {
                final parts = cookie.split(';').first.split('=');
                if (parts.length == 2)
                {
                    _cookies[parts[0].trim()] = parts[1].trim();
                }
            }
        }

        final data = _decryptResponse(resp.data, ts);
        return LoginResult.fromJson(jsonDecode(data));
    }

    /// 下载图片二进制数据
    Future<List<int>> downloadImage(String url) async
    {
        final resp = await _dio.get<List<int>>(
            url,
            options: Options(
                responseType: ResponseType.bytes,
                headers: {
                    ...JmConfig.appHeadersImage,
                },
            ),
        );
        return resp.data!;
    }

    /// 获取封面 URL
    /// URL: https://cdn-msp.{domain}/media/albums/{album_id}{size}.jpg
    String getAlbumCoverUrl(String albumId, {String size = '_3x4'})
    {
        final domain = _imageDomainList.first;
        return 'https://$domain/media/albums/${albumId}$size.jpg';
    }

    /// 获取章节图片 URL
    /// URL: https://cdn-msp.{domain}/media/photos/{photo_id}/{filename}
    String getImageUrl(String photoId, String filename)
    {
        final domain = _imageDomainList.first;
        return 'https://$domain/media/photos/$photoId/$filename';
    }

    /// 自动更新 API 域名
    /// 1. 请求域名服务器获取加密数据
    /// 2. decodeRespData(data, ts=0, secret=API_DOMAIN_SERVER_SECRET)
    /// 3. 解析 JSON 中的 Server 字段
    Future<void> updateApiDomains() async
    {
        for (final serverUrl in JmConfig.apiUrlDomainServerList)
        {
            try
            {
                final resp = await _dio.get<String>(serverUrl);
                var text = resp.data?.toString() ?? '';

                // 去掉开头非 ASCII 字符
                final startIndex = text.indexOf('{');
                if (startIndex > 0)
                {
                    text = text.substring(startIndex);
                }

                final decoded = JmCrypto.decodeDomainServerData(text);
                final json = jsonDecode(decoded) as Map<String, dynamic>;
                final servers = json['Server'] as List<dynamic>?;

                if (servers != null && servers.isNotEmpty)
                {
                    _domainList = servers.map((e) => e.toString()).toList();
                    break;
                }
            }
            catch (e)
            {
                continue;
            }
        }
    }

    /// 获取 Cookies（请求 /setting 接口）
    Future<void> ensureCookies() async
    {
        if (_cookies.isNotEmpty) return;

        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        try
        {
            final resp = await _getWithDomainFallback(
                '/setting',
                options: Options(headers: {
                    'token': token,
                    'tokenparam': tokenparam,
                }),
            );

            final setCookies = resp.headers['set-cookie'];
            if (setCookies != null)
            {
                for (final cookie in setCookies)
                {
                    final parts = cookie.split(';').first.split('=');
                    if (parts.length == 2)
                    {
                        _cookies[parts[0].trim()] = parts[1].trim();
                    }
                }
            }
        }
        catch (_)
        {
            // 忽略错误，cookies 可以为空
        }
    }

    /// 解密 API 响应数据
    String _decryptResponse(dynamic data, int ts)
    {
        // 如果 Dio 已自动解析为 Map，直接取 data 字段
        if (data is Map<String, dynamic>)
        {
            final encrypted = data['data']?.toString() ?? '';
            if (encrypted.isEmpty) return '{}';
            return JmCrypto.decodeDefaultRespData(encrypted, ts);
        }

        // 如果是字符串，先解析 JSON 再取 data 字段
        final dataStr = data.toString();
        try
        {
            final json = jsonDecode(dataStr) as Map<String, dynamic>;
            final encrypted = json['data']?.toString() ?? '';
            if (encrypted.isEmpty) return '{}';
            return JmCrypto.decodeDefaultRespData(encrypted, ts);
        }
        catch (_)
        {
            // 如果 JSON 解析失败，直接当加密数据处理
            return JmCrypto.decodeDefaultRespData(dataStr, ts);
        }
    }

    /// 带域名切换的 GET 请求
    /// 如果第一个域名失败，自动尝试下一个域名
    Future<Response<T>> _getWithDomainFallback<T>(
        String path, {
        Map<String, dynamic>? queryParameters,
        Options? options,
    }) async
    {
        DioException? lastError;

        for (var i = 0; i < _domainList.length; i++)
        {
            try
            {
                final domain = _domainList[i];
                final resp = await _dio.get<T>(
                    'https://$domain$path',
                    queryParameters: queryParameters,
                    options: options,
                );
                return resp;
            }
            on DioException catch (e)
            {
                lastError = e;
                // 如果还有下一个域名，继续尝试
                if (i < _domainList.length - 1) continue;
                rethrow;
            }
        }

        throw lastError ?? DioException(requestOptions: RequestOptions());
    }

    /// 获取当前时间戳（秒）
    int _currentTimestamp()
    {
        return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
}
