part of 'jm_client.dart';

/// JmClient 的核心基类，负责：
///   - Dio 实例、代理、cookie 拦截器初始化
///   - API / 图片域名列表管理
///   - 模块级域名缓存应用与持久化加载
///   - 通用底层工具（带域名切换的 GET、响应解密、图片 URL 构造等）
class _JmClientCore
{
    late final Dio _dio;
    List<String> _domainList = List.from(JmConfig.domainApiList);
    final List<String> _imageDomainList = List.from(JmConfig.domainImageList);
    final Map<String, String> _cookies = {};
    bool _initialized = false;

    /// API 域名是否被用户/外部代码手动覆盖过
    /// 设为 true 后 [updateApiDomains] / [_applyCachedDomains] 不再覆盖
    bool _apiDomainOverridden = false;

    /// 图片域名是否被用户/外部代码手动覆盖过
    bool _imageDomainOverridden = false;

    /// 代理地址（例如 "127.0.0.1:7890"），null 表示不用代理
    final String? proxyUrl;

    /// 是否启用代理
    final bool useProxy;

    // ===== 对外只读 getter =====

    /// 当前 API 域名是否被手动覆盖
    bool get isApiDomainOverridden => _apiDomainOverridden;

    /// 当前图片域名是否被手动覆盖
    bool get isImageDomainOverridden => _imageDomainOverridden;

    /// 获取当前 API 域名列表
    List<String> get domainList => _domainList;

    /// 获取当前图片域名列表
    List<String> get imageDomainList => _imageDomainList;

    /// 获取 Cookies
    Map<String, String> get cookies => _cookies;

    /// 获取 Dio 实例
    Dio get dio => _dio;

    _JmClientCore({this.proxyUrl, this.useProxy = false})
    {
        _dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: Map<String, dynamic>.from(JmConfig.appHeadersTemplate),
        ));

        // 应用代理
        if (useProxy && proxyUrl != null && proxyUrl!.isNotEmpty)
        {
            final adapter = _dio.httpClientAdapter;
            if (adapter is IOHttpClientAdapter)
            {
                adapter.createHttpClient = ()
                {
                    final client = HttpClient();
                    client.findProxy = (uri) => 'PROXY $proxyUrl';
                    client.badCertificateCallback = (cert, host, port) => true;
                    return client;
                };
            }
        }

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

        // 关键：构造时即触发模块级域名缓存加载（fire-and-forget）。
        // JmDomainCache 是模块级单例，多 JmClient 实例共享同一 future，
        // 不会重复请求域名服务器。
        // 同时加载用户持久化的自定义域名（覆盖默认）
        unawaited(_applyCachedDomains());
        unawaited(_loadPersistedDomains());
    }

    // ===== 域名管理 =====

    /// 设置 API 域名（手动覆盖，自动更新不再覆盖此值）
    /// 同时持久化到磁盘，下次启动时自动应用
    void setApiDomainList(List<String> domains)
    {
        _domainList = List<String>.from(domains);
        _apiDomainOverridden = true;
        _log('domain', '[manual] 设置 API 域名: ${_domainList.length} 个');
        unawaited(JmDomainPersistence.save(apiDomains: _domainList.toList()));
    }

    /// 设置图片域名（手动覆盖，自动更新不再覆盖此值）
    /// 同时持久化到磁盘
    void setImageDomainList(List<String> domains)
    {
        _imageDomainList
            ..clear()
            ..addAll(domains);
        _imageDomainOverridden = true;
        _log('domain', '[manual] 设置图片域名: ${_imageDomainList.length} 个');
        unawaited(JmDomainPersistence.save(imageDomains: _imageDomainList.toList()));
    }

    /// 随机打乱图片域名顺序
    void shuffleImageDomains()
    {
        _imageDomainList.shuffle();
        _imageDomainOverridden = true;
        _log('domain', '[shuffle] 图片域名: $_imageDomainList');
        unawaited(JmDomainPersistence.save(imageDomains: _imageDomainList.toList()));
    }

    /// 随机打乱 API 域名顺序
    void shuffleApiDomains()
    {
        _domainList.shuffle();
        _apiDomainOverridden = true;
        _log('domain', '[shuffle] API 域名: $_domainList');
        unawaited(JmDomainPersistence.save(apiDomains: _domainList.toList()));
    }

    /// 把 API 域名重置为 [JmConfig.domainApiList] 硬编码默认值
    void resetApiDomainsToDefault()
    {
        _domainList = List.from(JmConfig.domainApiList);
        _apiDomainOverridden = false;
        _log('domain', '[reset] API 域名恢复默认: $_domainList');
        unawaited(JmDomainPersistence.save(apiDomains: null));
    }

    /// 把图片域名重置为 [JmConfig.domainImageList] 硬编码默认值
    void resetImageDomainsToDefault()
    {
        _imageDomainList
            ..clear()
            ..addAll(JmConfig.domainImageList);
        _imageDomainOverridden = false;
        _log('domain', '[reset] 图片域名恢复默认: $_imageDomainList');
        unawaited(JmDomainPersistence.save(imageDomains: null));
    }

    /// 把所有域名重置为硬编码默认值
    void resetAllDomainsToDefault()
    {
        resetApiDomainsToDefault();
        resetImageDomainsToDefault();
    }

    /// 创建带代理配置的 Dio（用于域名测速等临时任务）
    /// 复用本客户端的代理设置，但不携带 cookies
    Dio createTestDio({Duration? connectTimeout, Duration? receiveTimeout})
    {
        final dio = Dio(BaseOptions(
            connectTimeout: connectTimeout ?? const Duration(seconds: 8),
            receiveTimeout: receiveTimeout ?? const Duration(seconds: 8),
        ));
        if (useProxy && proxyUrl != null && proxyUrl!.isNotEmpty)
        {
            final adapter = dio.httpClientAdapter;
            if (adapter is IOHttpClientAdapter)
            {
                adapter.createHttpClient = ()
                {
                    final client = HttpClient();
                    client.findProxy = (uri) => 'PROXY $proxyUrl';
                    client.badCertificateCallback = (cert, host, port) => true;
                    return client;
                };
            }
        }
        return dio;
    }

    /// 测试所有当前图片域名（流式，UI 可显示进度）
    Stream<DomainTestResult> testAllImageDomains()
    {
        final dio = createTestDio();
        return JmDomainCache.testAllImageDomains(
            dio, _imageDomainList.toList(),
        );
    }

    /// 测试所有当前 API 域名（流式）
    Stream<DomainTestResult> testAllApiDomains()
    {
        final dio = createTestDio();
        return JmDomainCache.testAllApiDomains(
            dio, _domainList.toList(),
        );
    }

    /// 自动更新 API 域名
    /// 委托给模块级 [JmDomainCache] 处理：
    ///   1. 多个 JmClient 共享同一缓存，不会重复请求域名服务器
    ///   2. 已有有效缓存时直接应用
    ///   3. 智能判断：仅当本实例的 _domainList / _imageDomainList
    ///      仍是 JmConfig 原始硬编码列表时才覆盖（不覆盖用户/外部手动设置的值）
    /// [forceReload] 为 true 时忽略缓存，强制重新拉取（图片下载全失败时使用）
    Future<void> updateApiDomains({bool forceReload = false}) async
    {
        if (forceReload)
        {
            _log('domain', '强制刷新域名缓存');
            final ok = await JmDomainCache.forceReload();
            if (!ok)
            {
                _log('domain', '强制刷新后仍无可用 API 域名');
            }
        }
        else
        {
            try
            {
                await JmDomainCache.ensureLoaded();
            }
            catch (e)
            {
                _log('domain', '模块级域名加载失败: $e');
            }
        }
        await _applyCachedDomains();
    }

    // ===== 图片 URL 构造 =====

    /// 获取封面 URL
    /// 域名基于 [albumId] 哈希稳定选择，确保同一本子多次调用得到相同 URL，
    /// 避免详情页等场景反复 build 时 [CachedNetworkImage] 缓存命中失败导致闪烁
    String getAlbumCoverUrl(String albumId, {String size = '_3x4'})
    {
        final domain = _pickRandomImageDomain(salt: albumId);
        return 'https://$domain/media/albums/$albumId$size.jpg';
    }

    /// 获取章节图片 URL
    String getImageUrl(String photoId, String filename)
    {
        final domain = _pickRandomImageDomain();
        return getImageUrlOnDomain(domain, photoId, filename);
    }

    /// 在指定域名上构造图片 URL（重试时调用）
    String getImageUrlOnDomain(String domain, String photoId, String filename)
    {
        return 'https://$domain/media/photos/$photoId/$filename';
    }

    /// 随机选一个图片域名（实现 Python 版的 shuffled 效果）
    /// 当 [salt] 不为空时使用 [salt] 的哈希取模，保证相同 [salt] 始终命中同一域名
    String _pickRandomImageDomain({String? salt})
    {
        if (_imageDomainList.isEmpty) return JmConfig.domainImageList.first;
        if (salt == null || salt.isEmpty)
        {
            final idx = Random().nextInt(_imageDomainList.length);
            return _imageDomainList[idx];
        }
        final idx = salt.hashCode.abs() % _imageDomainList.length;
        return _imageDomainList[idx];
    }

    // ===== 域名缓存与持久化 =====

    /// 判断 [_domainList] 是否仍是 JmConfig 中的原始硬编码列表
    bool get _isApiDomainListOriginal
    {
        if (_domainList.length != JmConfig.domainApiList.length)
        {
            return false;
        }
        return JmConfig.domainApiList
            .toSet()
            .difference(_domainList.toSet())
            .isEmpty;
    }

    /// 判断 [_imageDomainList] 是否仍是 JmConfig 中的原始硬编码列表
    bool get _isImageDomainListOriginal
    {
        if (_imageDomainList.length != JmConfig.domainImageList.length)
        {
            return false;
        }
        return JmConfig.domainImageList
            .toSet()
            .difference(_imageDomainList.toSet())
            .isEmpty;
    }

    /// 加载用户持久化的域名（fire-and-forget）
    Future<void> _loadPersistedDomains() async
    {
        try
        {
            final cfg = await JmDomainPersistence.load();
            if (cfg.hasImage)
            {
                _imageDomainList
                    ..clear()
                    ..addAll(cfg.imageDomains!);
                _imageDomainOverridden = true;
                _log('domain', '[persist] 加载图片域名: '
                    '${_imageDomainList.length} 个');
            }
            if (cfg.hasApi)
            {
                _domainList = List<String>.from(cfg.apiDomains!);
                _apiDomainOverridden = true;
                _log('domain', '[persist] 加载 API 域名: '
                    '${_domainList.length} 个');
            }
        }
        catch (e)
        {
            _log('domain', '持久化域名加载失败: $e');
        }
    }

    /// 应用 JmDomainCache 中的最新域名到本实例
    Future<void> _applyCachedDomains() async
    {
        try
        {
            await JmDomainCache.ensureLoaded();
        }
        catch (e)
        {
            _log('domain', '模块级域名加载失败: $e');
        }

        final api = JmDomainCache.latestApiList;
        final img = JmDomainCache.latestImageList;

        if (api != null && api.isNotEmpty
            && _isApiDomainListOriginal
            && !_apiDomainOverridden)
        {
            _domainList = List<String>.from(api);
            _log('domain', '应用缓存 API 域名: ${_domainList.length} 个');
        }
        if (img != null && img.isNotEmpty
            && _isImageDomainListOriginal
            && !_imageDomainOverridden)
        {
            _imageDomainList
                ..clear()
                ..addAll(img);
            _log('domain', '应用缓存图片域名: ${_imageDomainList.length} 个');
        }
    }

    // ===== 通用网络工具 =====

    /// 解密 API 响应数据
    String _decryptResponse(dynamic data, int ts)
    {
        if (data is Map<String, dynamic>)
        {
            final encrypted = data['data']?.toString() ?? '';
            if (encrypted.isEmpty) return '{}';
            return JmCrypto.decodeDefaultRespData(encrypted, ts);
        }

        // 对齐 Python jmcomic 2.7.8 的 BOM 修复（#585）：
        // 服务端部分响应可能携带 UTF-8 BOM（U+FEFF），jsonDecode 会因此抛 FormatException
        // 导致误走 AES 解密分支。Dart 的 trim() 会剥离 U+FEFF。
        final dataStr = data.toString().trim();
        try
        {
            final json = jsonDecode(dataStr) as Map<String, dynamic>;
            final encrypted = json['data']?.toString() ?? '';
            if (encrypted.isEmpty) return '{}';
            return JmCrypto.decodeDefaultRespData(encrypted, ts);
        }
        catch (_)
        {
            return JmCrypto.decodeDefaultRespData(dataStr, ts);
        }
    }

    /// 带域名切换的 GET 请求
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
