/// 禁漫客户端常量配置
class JmConfig
{
    // API 密钥
    static const String appTokenSecret = '185Hcomic3PAPP7R';
    static const String appTokenSecret2 = '18comicAPPContent';
    static const String appDataSecret = '185Hcomic3PAPP7R';
    static const String apiDomainServerSecret = 'diosfjckwpqpdfjkvnqQjsik';
    static const String appVersion = '2.0.26';

    // 图片分割阈值
    static const int scramble220980 = 220980;
    static const int scramble268850 = 268850;
    static const int scramble421926 = 421926;

    // 图片 CDN 域名
    static const List<String> domainImageList = [
        'cdn-msp.18comic.vip',
        'cdn-msp.18comic.cc',
    ];

    // API 域名（会从域名服务器自动更新）
    static const List<String> domainApiList = [
        'www.cdnhjk.net',
        'www.cdngwc.cc',
        'www.cdngwc.net',
        'www.cdngwc.club',
        'www.cdnutc.me',
    ];

    // 域名服务器
    static const List<String> apiUrlDomainServerList = [
        'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
        'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    ];

    // 分页大小
    static const int pageSizeSearch = 80;
    static const int pageSizeFavorite = 20;

    // 请求头模板
    static Map<String, String> get appHeadersTemplate => {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36',
        'Accept-Encoding': 'gzip, deflate',
    };

    // 图片请求头
    static Map<String, String> get appHeadersImage => {
        'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        'Referer': 'https://www.cdnhjk.net/',
    };

    // 默认下载线程数
    static const int defaultImageThreadCount = 5;
    static const int defaultPhotoThreadCount = 3;

    // 私有构造函数，防止实例化
    JmConfig._();
}
