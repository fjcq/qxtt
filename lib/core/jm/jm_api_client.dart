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

    /// 获取 scramble_id（HTML 兜底接口）
    /// GET {domain}/chapter_view_template?id={photo_id}&mode=vertical&page=0
    /// 注意: 此接口使用 APP_TOKEN_SECRET_2
    ///
    /// 修复说明：此前正则匹配失败时静默返回 0，会导致「无需解密的本子被错误解密」
    /// （get_num 中 aid < scramble_id → 0 的判断失效），表现为大面积花图。
    /// 现改为：失败时记录日志并抛出异常，交由调用方的任务失败/重试机制处理——
    /// 宁可下载失败也不产出错乱图片。正常流程应优先使用
    /// [PhotoDetail.scrambleId]（APP API 响应自带），本方法仅作兜底。
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

        // 匹配失败：记录响应片段便于排查（服务端改版/BOM/异常页），并抛异常
        _log('scramble_id', 'chapter_view_template 未匹配到 scramble_id, '
            'photoId=$photoId, respHead=${html.length > 200 ? html.substring(0, 200) : html}');
        throw Exception('获取 scramble_id 失败: photoId=$photoId '
            '(chapter_view_template 响应中未找到 scramble_id 字段)');
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
    ///
    /// 对齐 Python JmApiAbsClient.login：成功时解密后的 data 含
    /// uid/username/s(AVS) 等字段，AVS 作为会话 Cookie 存入 [_cookies]。
    /// 失败（网络异常）时逐域名重试，业务失败（账号密码错误）直接返回。
    Future<LoginResult> login(String username, String password) async
    {
        await _ensureInitialized();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        Object? lastError;
        for (var i = 0; i < _domainList.length; i++)
        {
            try
            {
                final resp = await _dio.post(
                    'https://${_domainList[i]}/login',
                    data: 'username=$username&password=$password',
                    options: Options(
                        headers: {
                            'token': token,
                            'tokenparam': tokenparam,
                            'Content-Type': 'application/x-www-form-urlencoded',
                        },
                    ),
                );

                final data = _decryptResponse(resp.data, ts);
                final result = LoginResult.fromJson(jsonDecode(data));

                // set-cookie 通用处理（服务端可能附带其它会话 cookie）
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

                // AVS 会话 token 优先取自解密响应的 s 字段
                if (result.success)
                {
                    _cookies['AVS'] = result.avs;
                }
                return result;
            }
            on DioException catch (e)
            {
                lastError = e;
                // 网络异常换下一个域名重试
                continue;
            }
        }

        throw lastError ??
            Exception('登录失败: 所有域名均不可用');
    }

    /// 恢复已持久化的登录会话（App 启动时调用）
    ///
    /// [avs] 为上次登录保存的 AVS 会话 token，非空时写入 [_cookies]，
    /// 后续收藏等需鉴权请求会自动携带。
    void restoreSession(String avs)
    {
        if (avs.isEmpty) return;
        _cookies['AVS'] = avs;
        _log('auth', '[restore] 恢复登录会话');
    }

    /// 当前是否持有登录会话（AVS token）
    bool get hasSession => _cookies['AVS']?.isNotEmpty ?? false;

    /// 获取收藏夹列表（需登录）
    /// GET {domain}/favorite?page={}&folder_id={}&o={}
    ///
    /// 对齐 Python JmApiAbsClient.favorite_folder：AVS Cookie 鉴权，
    /// 默认收藏夹 folder_id=0，o 为排序（mr=收藏时间）。
    Future<FavoriteResult> favorites({int page = 1, String orderBy = 'mr'}) async
    {
        _requireSession();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        final resp = await _getWithDomainFallback(
            '/favorite',
            queryParameters: {
                'page': page,
                'folder_id': '0',
                'o': orderBy,
            },
            options: Options(headers: {
                'token': token,
                'tokenparam': tokenparam,
            }),
        );

        final data = _decryptResponse(resp.data, ts);
        return FavoriteResult.fromJson(jsonDecode(data));
    }

    /// 切换本子收藏状态（需登录）
    /// POST {domain}/favorite，body: aid={albumId}
    ///
    /// 对齐 Python JmApiAbsClient.toggle_favorite_album：接口为 Toggle 语义，
    /// 已收藏则取消，未收藏则添加，响应 data.type 指示实际操作（add/remove）。
    Future<FavoriteToggleResult> toggleFavorite(String albumId) async
    {
        _requireSession();
        final ts = _currentTimestamp();
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        Object? lastError;
        for (var i = 0; i < _domainList.length; i++)
        {
            try
            {
                final resp = await _dio.post(
                    'https://${_domainList[i]}/favorite',
                    data: 'aid=$albumId',
                    options: Options(
                        headers: {
                            'token': token,
                            'tokenparam': tokenparam,
                            'Content-Type': 'application/x-www-form-urlencoded',
                        },
                    ),
                );

                final data = _decryptResponse(resp.data, ts);
                return FavoriteToggleResult.fromJson(jsonDecode(data));
            }
            on DioException catch (e)
            {
                lastError = e;
                continue;
            }
        }

        throw lastError ?? Exception('收藏操作失败: 所有域名均不可用');
    }

    /// 校验当前是否已登录，未登录抛出异常（收藏接口前置校验）
    void _requireSession()
    {
        if (!hasSession)
        {
            throw Exception('未登录，请先在设置页登录账号后再使用收藏功能');
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
}
