/// 应用配置模型
class AppConfigModel
{
    /// 下载目录
    String downloadDir;

    /// 图片下载线程数
    int imageThreadCount;

    /// 章节下载线程数
    int photoThreadCount;

    /// 是否解密图片
    bool decodeImage;

    /// 代理地址
    String proxyUrl;

    /// 是否使用代理
    bool useProxy;

    /// 主题模式: "dark" | "light" | "system"
    String themeMode;

    /// 阅读器模式: "vertical" | "horizontal" | "webtoon"
    String readerMode;

    /// 阅读缓存最大大小（字节），默认 2GB
    int readerCacheMaxSizeBytes;

    /// 在线阅读预加载页数（当前页前后各 N 页）
    int preloadPageCount;

    AppConfigModel({
        this.downloadDir = '',
        this.imageThreadCount = 5,
        this.photoThreadCount = 3,
        this.decodeImage = true,
        this.proxyUrl = '',
        this.useProxy = false,
        this.themeMode = 'dark',
        this.readerMode = 'vertical',
        this.readerCacheMaxSizeBytes = 2147483648,
        this.preloadPageCount = 2,
    });

    /// 从 JSON 创建
    factory AppConfigModel.fromJson(Map<String, dynamic> json)
    {
        return AppConfigModel(
            downloadDir: json['downloadDir'] as String? ?? '',
            imageThreadCount: json['imageThreadCount'] as int? ?? 5,
            photoThreadCount: json['photoThreadCount'] as int? ?? 3,
            decodeImage: json['decodeImage'] as bool? ?? true,
            proxyUrl: json['proxyUrl'] as String? ?? '',
            useProxy: json['useProxy'] as bool? ?? false,
            themeMode: json['themeMode'] as String? ?? 'dark',
            readerMode: json['readerMode'] as String? ?? 'vertical',
            readerCacheMaxSizeBytes:
                (json['readerCacheMaxSizeBytes'] as num?)?.toInt() ??
                2147483648,
            preloadPageCount:
                (json['preloadPageCount'] as num?)?.toInt() ?? 2,
        );
    }

    /// 转为 JSON
    Map<String, dynamic> toJson()
    {
        return {
            'downloadDir': downloadDir,
            'imageThreadCount': imageThreadCount,
            'photoThreadCount': photoThreadCount,
            'decodeImage': decodeImage,
            'proxyUrl': proxyUrl,
            'useProxy': useProxy,
            'themeMode': themeMode,
            'readerMode': readerMode,
            'readerCacheMaxSizeBytes': readerCacheMaxSizeBytes,
            'preloadPageCount': preloadPageCount,
        };
    }

    /// 复制并修改
    AppConfigModel copyWith({
        String? downloadDir,
        int? imageThreadCount,
        int? photoThreadCount,
        bool? decodeImage,
        String? proxyUrl,
        bool? useProxy,
        String? themeMode,
        String? readerMode,
        int? readerCacheMaxSizeBytes,
        int? preloadPageCount,
    })
    {
        return AppConfigModel(
            downloadDir: downloadDir ?? this.downloadDir,
            imageThreadCount: imageThreadCount ?? this.imageThreadCount,
            photoThreadCount: photoThreadCount ?? this.photoThreadCount,
            decodeImage: decodeImage ?? this.decodeImage,
            proxyUrl: proxyUrl ?? this.proxyUrl,
            useProxy: useProxy ?? this.useProxy,
            themeMode: themeMode ?? this.themeMode,
            readerMode: readerMode ?? this.readerMode,
            readerCacheMaxSizeBytes:
                readerCacheMaxSizeBytes ?? this.readerCacheMaxSizeBytes,
            preloadPageCount: preloadPageCount ?? this.preloadPageCount,
        );
    }
}
