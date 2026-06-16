import 'package:dio/dio.dart';

import '../jm/jm_client.dart';
import '../jm/jm_config.dart';
import '../jm/jm_crypto.dart';

/// API 请求拦截器 - 自动注入 token 和 cookie
class ApiInterceptor extends Interceptor
{
    final JmClient _jmClient;

    ApiInterceptor(this._jmClient);

    @override
    void onRequest(RequestOptions options, RequestInterceptorHandler handler) async
    {
        // 注入 token
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final (:token, :tokenparam) = JmCrypto.generateDefaultToken(ts);

        options.headers['token'] = token;
        options.headers['tokenparam'] = tokenparam;

        // 注入 cookies
        final cookies = _jmClient.cookies;
        if (cookies.isNotEmpty)
        {
            final cookieStr = cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
            options.headers['Cookie'] = cookieStr;
        }

        // 注入默认请求头
        options.headers.addAll(JmConfig.appHeadersTemplate);

        handler.next(options);
    }

    @override
    void onError(DioException err, ErrorInterceptorHandler handler) async
    {
        // 域名切换重试逻辑
        if (err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.connectionTimeout)
        {
            // 尝试更新域名
            try
            {
                await _jmClient.updateApiDomains();
                // 使用新域名重试
                final newUrl = _replaceDomain(err.requestOptions.uri);
                final newOptions = err.requestOptions.copyWith(
                    path: newUrl,
                );
                final response = await _jmClient.dio.fetch(newOptions);
                handler.resolve(response);
                return;
            }
            catch (_)
            {
                // 重试失败，继续报错
            }
        }

        handler.next(err);
    }

    /// 替换 URL 中的域名为当前可用域名
    String _replaceDomain(Uri uri)
    {
        final domains = _jmClient.domainList;
        if (domains.isEmpty) return uri.toString();

        final newUri = Uri(
            scheme: uri.scheme,
            host: domains.first,
            path: uri.path,
            query: uri.query,
            fragment: uri.fragment,
        );
        return newUri.toString();
    }
}
