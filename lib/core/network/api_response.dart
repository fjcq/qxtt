/// 统一 API 响应模型
class ApiResponse<T>
{
    /// 状态码
    final int code;

    /// 消息
    final String message;

    /// 数据
    final T? data;

    /// 是否成功
    bool get isSuccess => code == 200;

    const ApiResponse({
        required this.code,
        this.message = '',
        this.data,
    });

    /// 从 JSON 创建
    factory ApiResponse.fromJson(
        Map<String, dynamic> json,
        T Function(dynamic)? fromJsonT,
    )
    {
        return ApiResponse(
            code: json['code'] as int? ?? -1,
            message: json['message']?.toString() ?? '',
            data: json['data'] != null && fromJsonT != null
                ? fromJsonT(json['data'])
                : null,
        );
    }
}
