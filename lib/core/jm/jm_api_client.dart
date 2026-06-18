part of 'jm_client.dart';

/// JmClient 的 API 请求层，封装所有禁漫业务接口：
///   - 搜索、本子详情、章节详情
///   - scramble_id 获取
///   - 分类浏览
///   - 登录与 cookies
class _JmApiClient extends _JmClientCore
{
    _JmApiClient({super.proxyUrl, super.useProxy});

    /// 确保初始化完成（更新域名 + 获取 cookies）
    Future<void> _ensureInitialized() async
    {
        if (_initialized) return;
        _initialized = true;

        try
        {
            await _applyCachedDomains();
        }
        catch (_)
        {
            // 域名更新失败，使用默认域名
        }

        try
        {
            await ensureCookies();
        }
        catch (_)
        {
            // cookies 获取失败，继续使用
        }
    }

    /// 搜索漫画
    /// GET {domain}/search?search_query={}&page={}&main_tag={}&o={}&t={}
    /// main_tag: 0=站内, 1=作品, 2=作者, 3=标签, 4=角色
    Future<SearchResult> search(
        String query, {
        int page = 1,
        int mainTag = 0,
        String orderBy = 'mr',
        String time = 'a',
    }) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

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
}
