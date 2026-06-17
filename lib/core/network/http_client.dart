import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// HTTP 客户端封装
class HttpClient
{
    late final Dio _dio;

    /// 获取 Dio 实例
    Dio get dio => _dio;

    /// 代理地址（例如 "127.0.0.1:7890"）
    final String? proxyUrl;

    HttpClient({
        this.proxyUrl,
        Duration connectTimeout = const Duration(seconds: 15),
        Duration receiveTimeout = const Duration(seconds: 30),
    })
    {
        _dio = Dio(BaseOptions(
            connectTimeout: connectTimeout,
            receiveTimeout: receiveTimeout,
        ));
        _applyProxy();
    }

    /// 将代理设置到底层 io.HttpClient
    void _applyProxy()
    {
        if (proxyUrl == null || proxyUrl!.isEmpty) return;
        final adapter = _dio.httpClientAdapter;
        if (adapter is IOHttpClientAdapter)
        {
            adapter.createHttpClient = ()
            {
                final client = io.HttpClient();
                // findProxy: 所有请求都走代理
                client.findProxy = (uri) => 'PROXY $proxyUrl';
                // 跳过代理身份认证弹窗
                client.badCertificateCallback = (cert, host, port) => true;
                return client;
            };
        }
    }

    /// GET 请求
    Future<Response<T>> get<T>(
        String path, {
        Map<String, dynamic>? queryParameters,
        Options? options,
    }) async
    {
        return _dio.get<T>(
            path,
            queryParameters: queryParameters,
            options: options,
        );
    }

    /// POST 请求
    Future<Response<T>> post<T>(
        String path, {
        dynamic data,
        Options? options,
    }) async
    {
        return _dio.post<T>(path, data: data, options: options);
    }

    /// 下载文件
    Future<Response> download(
        String urlPath,
        String savePath, {
        ProgressCallback? onReceiveProgress,
        Options? options,
    }) async
    {
        return _dio.download(
            urlPath,
            savePath,
            onReceiveProgress: onReceiveProgress,
            options: options,
        );
    }
}
