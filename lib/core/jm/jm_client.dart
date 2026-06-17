import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'jm_config.dart';
import 'jm_crypto.dart';
import 'jm_domain_persistence.dart';
import 'jm_entity.dart';

/// 内部统一日志（输出到 IDE 控制台/Flutter DevTools，不污染业务日志）
void _log(String tag, String message)
{
    // 使用 dart:developer.log，可在 DevTools 中按 tag 过滤
    developer.log(message, name: 'jmcomic.$tag');
}

/// 域名测速结果
class DomainTestResult
{
    /// 域名（不含协议）
    final String domain;

    /// 延迟（毫秒），null 表示失败
    final int? latencyMs;

    /// HTTP 状态码（HEAD 请求后），null 表示请求未发出
    final int? statusCode;

    /// 错误信息，成功时为 null
    final String? error;

    const DomainTestResult({
        required this.domain,
        required this.latencyMs,
        required this.statusCode,
        required this.error,
    });

    bool get isSuccess => error == null;

    /// 速度档位（UI 显示颜色）
    /// 0: 极快 (< 200ms)   → 绿
    /// 1: 正常 (200~800ms)  → 黄
    /// 2: 慢 (> 800ms)     → 橙
    /// 3: 失败              → 红
    int get speedLevel
    {
        if (!isSuccess) return 3;
        final ms = latencyMs ?? 0;
        if (ms < 200) return 0;
        if (ms < 800) return 1;
        return 2;
    }

    /// 人类可读的延迟描述
    String get displayLatency
    {
        if (!isSuccess) return '失败';
        final ms = latencyMs ?? 0;
        if (ms < 1000) return '${ms}ms';
        return '${(ms / 1000).toStringAsFixed(2)}s';
    }

    @override
    String toString()
    {
        if (isSuccess)
        {
            return 'DomainTestResult($domain, ${latencyMs}ms, $statusCode)';
        }
        return 'DomainTestResult($domain, fail: $error)';
    }
}

/// 模块级域名缓存（参考 Python 版 JmModuleConfig.DOMAIN_API_UPDATED_LIST）
/// 三态:
///   - null  → 尚未尝试
///   - []    → 已尝试，所有源都失败（done=false 状态）
///   - [...] → 已成功获取到的最新列表
/// 静态字段共享给所有 JmClient 实例，避免重复请求域名服务器。
class JmDomainCache
{
    /// 最新 API 域名列表
    static List<String>? _latestApiList;

    /// 最新图片域名列表
    static List<String>? _latestImageList;

    /// 进行中的更新任务（多个 JmClient 共享同一 future）
    static Future<void>? _inFlight;

    /// 获取当前缓存的最新 API 域名（可能为 null 或空列表）
    static List<String>? get latestApiList => _latestApiList;

    /// 获取当前缓存的最新图片域名（可能为 null 或空列表）
    static List<String>? get latestImageList => _latestImageList;

    /// 确保域名已尝试加载一次
    /// - 多个并发调用方复用同一 inFlight future（参考 Python 版的 client_update_domain_lock）
    /// - 完成后用空列表作为"已尝试过但失败"的标记，避免下次重复请求
    static Future<void> ensureLoaded() async
    {
        // 已完成（成功或失败都算 done）
        if (_latestApiList != null)
        {
            return;
        }
        // 已有进行中的任务，等待它完成
        if (_inFlight != null)
        {
            return _inFlight!;
        }
        // 启动新的更新任务
        final completer = Completer<void>();
        _inFlight = completer.future;
        try
        {
            await _doLoad();
        }
        finally
        {
            // 不管成功失败，都把 inFlight 置空（但保留缓存以表示"已尝试"）
            _inFlight = null;
            completer.complete();
        }
    }

    /// 强制重新加载（忽略缓存，下载失败重试时用）
    /// 返回 true 表示有获取到至少一个 API 域名
    static Future<bool> forceReload() async
    {
        // 重置缓存以绕过"已完成"短路
        _latestApiList = null;
        _latestImageList = null;
        await ensureLoaded();
        return _latestApiList != null && _latestApiList!.isNotEmpty;
    }

    /// 实际从远程服务器拉取并解密
    static Future<void> _doLoad() async
    {
        // 使用一个临时 Dio 实例，避免被任何 JmClient 的代理配置影响
        // （JmDomainCache 是模块级，不应被特定客户端的代理设置污染）
        final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
        ));

        for (final serverUrl in JmConfig.apiUrlDomainServerList)
        {
            try
            {
                _log('domain', '[cache] 请求域名服务器: $serverUrl');
                final resp = await dio.get<String>(serverUrl);
                final status = resp.statusCode ?? -1;
                _log('domain', '[cache] 域名服务器响应: status=$status, '
                    'len=${resp.data?.length ?? 0}');
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
                final imgServers = json['ImgServer'] as List<dynamic>?
                    ?? json['imgServer'] as List<dynamic>?
                    ?? json['imageServer'] as List<dynamic>?
                    ?? json['ImageServer'] as List<dynamic>?;

                if (servers != null && servers.isNotEmpty)
                {
                    _latestApiList = servers.map((e) => e.toString()).toList();
                    _log('domain', '[cache] 已缓存 API 域名: '
                        '${_latestApiList!.length} 个');
                }
                if (imgServers != null && imgServers.isNotEmpty)
                {
                    _latestImageList = imgServers.map((e) => e.toString()).toList();
                    _log('domain', '[cache] 已缓存图片域名: '
                        '${_latestImageList!.length} 个');
                }
                else
                {
                    _log('domain', '[cache] 未发现图片域名字段');
                }
                // 成功（或部分成功）就跳出（即使 ImgServer 缺失）
                if (_latestApiList != null && _latestApiList!.isNotEmpty)
                {
                    return;
                }
            }
            catch (e)
            {
                _log('domain', '[cache] 域名服务器 $serverUrl 失败: $e');
                continue;
            }
        }
        // 走到这里：所有源都失败，置空列表作为"已尝试过"标记
        _latestApiList = const <String>[];
        _latestImageList = const <String>[];
        _log('domain', '[cache] 所有域名服务器都失败，标记为 done');
    }

    /// 测试单个域名
    /// 用 HEAD 请求，测量首字节延迟
    static Future<DomainTestResult> _testOneDomain(
        Dio dio,
        String domain,
    ) async
    {
        final stopwatch = Stopwatch()..start();
        try
        {
            final resp = await dio.head<Map<String, dynamic>>(
                'https://$domain/',
            );
            stopwatch.stop();
            return DomainTestResult(
                domain: domain,
                latencyMs: stopwatch.elapsedMilliseconds,
                statusCode: resp.statusCode,
                error: null,
            );
        }
        catch (e)
        {
            stopwatch.stop();
            return DomainTestResult(
                domain: domain,
                latencyMs: stopwatch.elapsedMilliseconds,
                statusCode: null,
                error: e.toString(),
            );
        }
    }

    /// 测试所有图片域名（流式输出，每个域名完成时立即 emit）
    /// [dio] 复用一个 Dio 实例（带代理配置）
    /// [domains] 要测试的域名列表
    static Stream<DomainTestResult> testAllImageDomains(
        Dio dio,
        List<String> domains,
    )
    {
        _log('image', '开始测速 ${domains.length} 个图片域名');
        return _streamResults(dio, domains);
    }

    /// 测试所有 API 域名（流式输出）
    static Stream<DomainTestResult> testAllApiDomains(
        Dio dio,
        List<String> domains,
    )
    {
        _log('domain', '开始测速 ${domains.length} 个 API 域名');
        return _streamResults(dio, domains);
    }

    /// 把并行测速包装成 Stream，结果按完成顺序输出
    /// UI 监听 stream 即可显示进度：每收到一个 result 进度 +1
    static Stream<DomainTestResult> _streamResults(
        Dio dio,
        List<String> domains,
    )
    {
        final controller = StreamController<DomainTestResult>();
        if (domains.isEmpty)
        {
            // 异步关闭，避免监听者错过
            Future.microtask(() => controller.close());
            return controller.stream;
        }
        var pending = domains.length;
        var failed = 0;
        for (final d in domains)
        {
            _testOneDomain(dio, d).then((r)
            {
                if (!controller.isClosed) controller.add(r);
                if (!r.isSuccess) failed++;
            }).catchError((e, st)
            {
                if (!controller.isClosed)
                {
                    controller.add(DomainTestResult(
                        domain: d, latencyMs: null,
                        statusCode: null, error: e.toString(),
                    ));
                }
                failed++;
            }).whenComplete(() {
                pending--;
                if (pending == 0 && !controller.isClosed)
                {
                    controller.close();
                    _log('domain', '测速完成: '
                        '${domains.length - failed}/${domains.length} 成功');
                }
            });
        }
        return controller.stream;
    }

    // 私有构造函数
    JmDomainCache._();
}

/// 禁漫 API 客户端
class JmClient
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

    // ===== 对外只读 getter（已存在：domainList / imageDomainList） =====

    /// 当前 API 域名是否被手动覆盖
    bool get isApiDomainOverridden => _apiDomainOverridden;

    /// 当前图片域名是否被手动覆盖
    bool get isImageDomainOverridden => _imageDomainOverridden;

    // ===== 对外操作接口 =====

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
    /// 每个域名完成时立即 emit 一个 [DomainTestResult]
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

    /// 判断 [_domainList] 是否仍是 JmConfig 中的原始硬编码列表
    /// （用户/外部代码没手动覆盖过）
    bool get _isApiDomainListOriginal
    {
        if (_domainList.length != JmConfig.domainApiList.length)
        {
            return false;
        }
        // 注意：原始列表元素互不相同，可以直接 set 比对
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

    JmClient({this.proxyUrl, this.useProxy = false})
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

    /// 加载用户持久化的域名（fire-and-forget）
    /// 如果存在持久化配置，则覆盖硬编码默认值
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
    /// - 仅当 _domainList / _imageDomainList 仍是原始硬编码列表时才覆盖
    ///   （防止覆盖用户/外部代码手动设置的值）
    /// - 多个 JmClient 共享同一 JmDomainCache 缓存
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

    /// 确保初始化完成（更新域名 + 获取 cookies）
    Future<void> _ensureInitialized() async
    {
        if (_initialized) return;
        _initialized = true;

        // 等待构造阶段启动的域名更新任务完成
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
    /// 仿照 Python 版 request_with_retry：先在当前域名上重试 N 次，
    /// 全部失败后自动切换到下一个域名，遍历所有图片域名。
    /// 使用 [ResponseType.stream] 流式消费确保数据完整（[ResponseType.bytes]
    /// 在 chunked/部分 CDN 环境下可能少收最后几字节，导致后续解码失败）。
    /// 当所有域名都失败时，会自动调用 [updateApiDomains]（forceReload 强制刷新
    /// 模块级 JmDomainCache）并再尝试一轮。
    /// [photoId] 章节 ID
    /// [filename] 图片文件名
    Future<List<int>> downloadImage(String photoId, String filename,
        {CancelToken? cancelToken}) async
    {
        try
        {
            return await _downloadImageOnce(photoId, filename, cancelToken);
        }
        on Exception catch (e)
        {
            // 全部域名失败 → 强制刷新模块级缓存后再来一次
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
            // 用新域名再尝试一轮（只一次，不递归）
            return await _downloadImageOnce(photoId, filename, cancelToken,
                onRetryAfterDomainUpdate: true);
        }
    }

    /// 单轮下载（遍历 _imageDomainList 当前的快照，3 次重试/域名）
    /// [onRetryAfterDomainUpdate] 为 true 时，日志会标注这是刷新后的重试
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
                    // 关键：使用 stream 模式，避免 bytes 模式在某些 CDN/代理上
                    // 截断最后几字节（表现为解码时 "长度差 1" 错误）。
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

                    // 完整消费 stream 并拼接成连续 bytes
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

                    // 长度校验：与 Content-Length 对比（chunked 时无该头，跳过）
                    final contentLength = resp.headers.value(
                        HttpHeaders.contentLengthHeader,
                    );
                    if (contentLength != null)
                    {
                        final expected = int.tryParse(contentLength) ?? -1;
                        if (expected > 0 && expected != received)
                        {
                            throw DioException(
                                requestOptions: RequestOptions(path: url),
                                message:
                                    '图片长度不匹配: 期望 $expected 字节, 实际 $received 字节',
                            );
                        }
                    }
                    return bytes;
                }
                on DioException catch (e)
                {
                    lastError = e;
                    // 被取消的请求不重试
                    if (CancelToken.isCancel(e)) rethrow;
                    // 429/4xx 不重试
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
            // 全部域名失败 → 强制刷新模块级缓存后再来一次
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

        // 已存在的本地文件大小
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

                    // 探测远程文件大小（HEAD 请求）
                    var totalSize = localSize;
                    try
                    {
                        final headResp = await _dio.head<dynamic>(
                            url,
                            options: Options(
                                headers: {
                                    ...JmConfig.appHeadersImage,
                                },
                                // 避免 dio 自动跟随重定向导致的 404 误判
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

                    // 本地已与远程等大，视为已下载
                    if (totalSize > 0 && localSize >= totalSize)
                    {
                        return false;
                    }

                    // 构造请求头，支持 Range 续传
                    final headers = <String, dynamic>{
                        ...JmConfig.appHeadersImage,
                    };
                    if (localSize > 0)
                    {
                        headers['Range'] = 'bytes=$localSize-';
                    }

                    // dio.download 会以 append 模式续写文件
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
                    // 被取消的请求不重试
                    if (CancelToken.isCancel(e)) rethrow;
                    // 416 表示 Range 不被支持，放弃 Range 重试整图
                    if (e.response?.statusCode == 416)
                    {
                        // 重置 localSize 重头下载
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
                    // 429/4xx 不重试
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

    /// 获取封面 URL
    /// URL: https://cdn-msp.{domain}/media/albums/{album_id}{size}.jpg
    String getAlbumCoverUrl(String albumId, {String size = '_3x4'})
    {
        // 随机选一个起点，分散流量
        final domain = _pickRandomImageDomain();
        return 'https://$domain/media/albums/$albumId$size.jpg';
    }

    /// 获取章节图片 URL
    /// URL: https://cdn-msp.{domain}/media/photos/{photo_id}/{filename}
    /// [photoId] 章节 ID
    /// [filename] 图片文件名
    String getImageUrl(String photoId, String filename)
    {
        // 随机选一个起点，分散流量
        final domain = _pickRandomImageDomain();
        return getImageUrlOnDomain(domain, photoId, filename);
    }

    /// 在指定域名上构造图片 URL（重试时调用）
    String getImageUrlOnDomain(String domain, String photoId, String filename)
    {
        return 'https://$domain/media/photos/$photoId/$filename';
    }

    /// 随机选一个图片域名（实现 Python 版的 shuffled 效果）
    String _pickRandomImageDomain()
    {
        if (_imageDomainList.isEmpty) return JmConfig.domainImageList.first;
        // 用当前时间种子产生伪随机
        final idx = Random().nextInt(_imageDomainList.length);
        return _imageDomainList[idx];
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
