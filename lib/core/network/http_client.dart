import 'package:dio/dio.dart';

/// HTTP 客户端封装
class HttpClient
{
    late final Dio _dio;

    /// 获取 Dio 实例
    Dio get dio => _dio;

    HttpClient({
        String? proxyUrl,
        Duration connectTimeout = const Duration(seconds: 15),
        Duration receiveTimeout = const Duration(seconds: 30),
    })
    {
        _dio = Dio(BaseOptions(
            connectTimeout: connectTimeout,
            receiveTimeout: receiveTimeout,
        ));
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
