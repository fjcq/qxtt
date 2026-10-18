import '../jm/jm_config.dart';

/// 禁漫数据实体定义
class SearchResult
{
    /// 总数
    final int total;

    /// 总页数
    final int pageCount;

    /// 搜索结果列表
    final List<SearchItem> results;

    const SearchResult({
        required this.total,
        required this.pageCount,
        required this.results,
    });

    factory SearchResult.fromJson(Map<String, dynamic> json)
    {
        final list = (json['content'] as List<dynamic>? ?? [])
            .map((e) => SearchItem.fromJson(e as Map<String, dynamic>))
            .toList();
        return SearchResult(
            total: json['total'] as int? ?? 0,
            pageCount: json['page_count'] as int? ?? 0,
            results: list,
        );
    }
}

/// 搜索结果项
class SearchItem
{
    /// 本子 ID
    final String id;

    /// 标题
    final String title;

    /// 作者
    final String author;

    /// 标签
    final List<String> tags;

    /// 封面 URL
    final String coverUrl;

    /// 页数
    final int pageCount;

    /// 分类
    final String category;

    const SearchItem({
        required this.id,
        required this.title,
        this.author = '',
        this.tags = const [],
        this.coverUrl = '',
        this.pageCount = 0,
        this.category = '',
    });

    factory SearchItem.fromJson(Map<String, dynamic> json)
    {
        final id = json['id']?.toString() ?? '';
        // API 返回的 image 字段通常为空，需要根据 id 拼接封面 URL
        final imageField = json['image']?.toString() ?? json['cover']?.toString() ?? '';
        final coverUrl = imageField.isNotEmpty
            ? imageField
            : 'https://${JmConfig.domainImageList.first}/media/albums/${id}_3x4.jpg';

        // category 可能是字符串或 {id, title} 对象
        String category = '';
        final catRaw = json['category'];
        if (catRaw is String)
        {
            category = catRaw;
        }
        else if (catRaw is Map)
        {
            category = catRaw['title']?.toString() ?? '';
        }

        // page_count 可能不存在或类型不同
        int pageCount = 0;
        final pcRaw = json['page_count'];
        if (pcRaw is int)
        {
            pageCount = pcRaw;
        }
        else if (pcRaw != null)
        {
            pageCount = int.tryParse(pcRaw.toString()) ?? 0;
        }

        return SearchItem(
            id: id,
            title: json['name']?.toString() ?? json['title']?.toString() ?? '',
            author: json['author']?.toString() ?? '',
            tags: (json['tags'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            coverUrl: coverUrl,
            pageCount: pageCount,
            category: category,
        );
    }
}

/// 本子详情
class AlbumDetail
{
    /// 本子 ID
    final String albumId;

    /// 标题
    final String name;

    /// 原始标题
    final String oname;

    /// 作者
    final String author;

    /// 作者列表
    final List<String> authors;

    /// 标签
    final List<String> tags;

    /// 页数
    final int pageCount;

    /// 章节数
    final int episodeCount;

    /// 章节列表
    final List<Episode> episodes;

    /// 发布日期
    final String pubDate;

    /// 浏览量
    final String views;

    /// 点赞数
    final String likes;

    /// 简介
    final String description;

    /// 封面 URL
    final String coverUrl;

    const AlbumDetail({
        required this.albumId,
        required this.name,
        this.oname = '',
        this.author = '',
        this.authors = const [],
        this.tags = const [],
        this.pageCount = 0,
        this.episodeCount = 0,
        this.episodes = const [],
        this.pubDate = '',
        this.views = '',
        this.likes = '',
        this.description = '',
        this.coverUrl = '',
    });

    factory AlbumDetail.fromJson(Map<String, dynamic> json)
    {
        final albumId = json['id']?.toString() ?? '';
        final name = json['name']?.toString() ?? '';

        var episodeList =
            (json['series'] as List<dynamic>? ?? [])
                .map((e) => Episode.fromJson(e as Map<String, dynamic>))
                .toList();

        // 对齐 Python jm_entity.py JmAlbumDetail.__init__ 的逻辑:
        // 有的 album 没有章节（series 为空, series_id=="0"），则自成一章。
        // 此时用 albumId 作为 photoId, "1" 作为序号, album 名称作为章节名。
        // 否则单本/短篇类漫画详情页将看不到章节列表, 无法阅读或下载。
        if (episodeList.isEmpty)
        {
            episodeList = [
                Episode(photoId: albumId, index: '1', name: name),
            ];
        }

        // 当前 API 响应中不再包含 episode_count 字段，需根据实际章节列表计算。
        // 若后续 API 恢复该字段，优先使用接口值作为兼容。
        var episodeCount = episodeList.length;
        final ecRaw = json['episode_count'];
        if (ecRaw is int)
        {
            episodeCount = ecRaw;
        }
        else if (ecRaw != null)
        {
            episodeCount = int.tryParse(ecRaw.toString()) ?? episodeList.length;
        }

        // 封面 URL：image 为空时根据 id 拼接
        final imageField = json['image']?.toString() ?? json['cover']?.toString() ?? '';
        final coverUrl = imageField.isNotEmpty
            ? imageField
            : 'https://${JmConfig.domainImageList.first}/media/albums/${albumId}_3x4.jpg';

        // page_count 安全解析
        int pageCount = 0;
        final pcRaw = json['page_count'];
        if (pcRaw is int)
        {
            pageCount = pcRaw;
        }
        else if (pcRaw != null)
        {
            pageCount = int.tryParse(pcRaw.toString()) ?? 0;
        }

        return AlbumDetail(
            albumId: albumId,
            name: json['name']?.toString() ?? '',
            oname: json['oname']?.toString() ?? '',
            author: json['author']?.toString() ?? '',
            authors: (json['authors'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            tags: (json['tags'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            pageCount: pageCount,
            episodeCount: episodeCount,
            episodes: episodeList,
            pubDate: json['pub_date']?.toString() ?? '',
            views: json['views']?.toString() ?? '',
            likes: json['likes']?.toString() ?? '',
            description: json['description']?.toString() ?? '',
            coverUrl: coverUrl,
        );
    }
}

/// 章节信息
class Episode
{
    /// 章节 ID
    final String photoId;

    /// 序号
    final String index;

    /// 标题
    final String name;

    const Episode({
        required this.photoId,
        required this.index,
        required this.name,
    });

    factory Episode.fromJson(Map<String, dynamic> json)
    {
        // 对齐 Python jm_toolkit.py JmAdapter.post_adapt_album:
        //   episode_list.append((chapter.id, chapter.sort, chapter.name))
        // JM API 返回的 series 元素字段为 id / sort / name, 而非 index。
        // 之前误用 json['index'] 会始终得到空字符串, 导致序号显示空白。
        final index = json['sort']?.toString() ?? json['index']?.toString() ?? '';
        return Episode(
            photoId: json['id']?.toString() ?? '',
            index: index,
            name: json['name']?.toString() ?? '',
        );
    }

    /// 章节显示名称
    ///
    /// JM API 的 series 字段中, 许多章节没有独立标题 (name 为空字符串)。
    /// 此时回退为 "第N话" 格式, 与 Python jmcomic 库 JmPhotoDetail.indextitle
    /// (f'第{album_index}話 {name}') 及 CLI 输出 (f'第{pindex}話  {pname}') 行为一致,
    /// 避免 UI 章节列表/阅读器顶部栏出现空白标题。
    /// 当 index 也缺失时, 兜底为 "未命名章节"。
    String get displayName
    {
        if (name.trim().isNotEmpty) return name;
        if (index.trim().isNotEmpty) return '第$index话';
        return '未命名章节';
    }
}

/// 章节详情
class PhotoDetail
{
    /// 章节 ID
    final String photoId;

    /// 本子 ID
    final String albumId;

    /// 标题
    final String name;

    /// 图片文件名列表
    final List<String> pageArr;

    /// 图片域名
    final String imageDomain;

    /// 图片后缀
    final String imageSuffix;

    /// 解密参数（scramble_id）
    /// 对齐 Python jmcomic 库：JmPhotoDetail 本身携带 scramble_id 字段，
    /// 优先使用该值，仅当缺失（0）时才回退到 chapter_view_template HTML 接口获取。
    final int scrambleId;

    const PhotoDetail({
        required this.photoId,
        required this.albumId,
        this.name = '',
        this.pageArr = const [],
        this.imageDomain = '',
        this.imageSuffix = '.jpg',
        this.scrambleId = 0,
    });

    factory PhotoDetail.fromJson(Map<String, dynamic> json)
    {
        final photoId = json['id']?.toString() ?? '';
        // 对齐 Python jm_entity.py JmPhotoDetail.album_id:
        //   series_id == 0 (单本) → album_id = photo_id
        //   series_id != 0         → album_id = str(series_id)
        // API 可能返回 aid 或 series_id，优先使用 series_id
        final seriesIdRaw = json['series_id']?.toString() ?? json['aid']?.toString() ?? '0';
        final seriesId = int.tryParse(seriesIdRaw) ?? 0;
        final albumId = seriesId == 0 ? photoId : seriesIdRaw;

        return PhotoDetail(
            photoId: photoId,
            albumId: albumId,
            name: json['name']?.toString() ?? '',
            pageArr: (json['images'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            imageDomain: json['domain']?.toString() ?? '',
            imageSuffix: json['suffix']?.toString() ?? '.jpg',
            // scramble_id 安全解析：API 响应通常为 int，防御性兼容字符串
            scrambleId: json['scramble_id'] is int
                ? json['scramble_id'] as int
                : int.tryParse(json['scramble_id']?.toString() ?? '') ?? 0,
        );
    }
}

/// 登录结果
class LoginResult
{
    /// 是否成功（解密后 data 含 uid 且 AVS token 非空）
    final bool success;

    /// 用户名
    final String username;

    /// 消息（成功时为欢迎语，失败时为错误提示）
    final String message;

    /// 用户 ID
    final String uid;

    /// 会话 token（即响应中的 s 字段，作为 Cookie AVS 携带）
    final String avs;

    /// 用户头像
    final String photo;

    /// 收藏本子数
    final int albumFavorites;

    /// 收藏容量上限
    final int albumFavoritesMax;

    const LoginResult({
        required this.success,
        this.username = '',
        this.message = '',
        this.uid = '',
        this.avs = '',
        this.photo = '',
        this.albumFavorites = 0,
        this.albumFavoritesMax = 0,
    });

    /// 从解密后的登录响应解析
    ///
    /// 对齐 Python jmcomic JmApiAbsClient.login 的响应结构：
    /// 成功时 data 含 uid/username/s(AVS)/photo/album_favorites 等字段。
    factory LoginResult.fromJson(Map<String, dynamic> json)
    {
        final uid = json['uid']?.toString() ?? '';
        final avs = json['s']?.toString() ?? '';
        return LoginResult(
            success: uid.isNotEmpty && avs.isNotEmpty,
            username: json['username']?.toString() ?? '',
            message: json['message']?.toString() ?? '',
            uid: uid,
            avs: avs,
            photo: json['photo']?.toString() ?? '',
            albumFavorites: (json['album_favorites'] as num?)?.toInt() ?? 0,
            albumFavoritesMax: (json['album_favorites_max'] as num?)?.toInt() ?? 0,
        );
    }
}

/// 收藏夹列表结果
///
/// GET /favorite 解密后的 data 结构（对齐 Python parse_api_to_favorite_page）：
/// `{list: [SearchItem 结构数组], total: N, ...}`
class FavoriteResult
{
    /// 收藏总数
    final int total;

    /// 收藏列表（元素与搜索结果项同结构）
    final List<SearchItem> results;

    const FavoriteResult({
        required this.total,
        required this.results,
    });

    factory FavoriteResult.fromJson(Map<String, dynamic> json)
    {
        final list = (json['list'] as List<dynamic>? ?? [])
            .map((e) => SearchItem.fromJson(e as Map<String, dynamic>))
            .toList();
        return FavoriteResult(
            total: (json['total'] as num?)?.toInt() ?? 0,
            results: list,
        );
    }
}

/// 收藏/取消收藏操作结果
///
/// POST /favorite 为 Toggle 语义：已收藏则取消，未收藏则添加。
/// 解密后的 data 含 `{type: 'add'|'remove', msg: ...}`
class FavoriteToggleResult
{
    /// 操作类型：add=已添加收藏，remove=已取消收藏
    final String type;

    /// 提示消息
    final String message;

    const FavoriteToggleResult({
        required this.type,
        this.message = '',
    });

    factory FavoriteToggleResult.fromJson(Map<String, dynamic> json)
    {
        return FavoriteToggleResult(
            type: json['type']?.toString() ?? '',
            message: json['msg']?.toString() ?? '',
        );
    }
}

/// 图片详情（用于下载）
class ImageDetail
{
    /// 图片 URL
    final String url;

    /// 文件名
    final String filename;

    /// 本子 ID
    final int aid;

    /// 章节 ID
    final String photoId;

    /// 保存路径
    final String savePath;

    const ImageDetail({
        required this.url,
        required this.filename,
        required this.aid,
        required this.photoId,
        required this.savePath,
    });
}
