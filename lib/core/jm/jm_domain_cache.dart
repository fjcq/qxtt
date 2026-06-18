part of 'jm_client.dart';

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
