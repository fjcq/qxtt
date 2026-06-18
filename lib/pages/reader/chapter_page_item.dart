import 'package:flutter/foundation.dart';

/// 章节单页信息
///
/// 用于混合渲染：优先使用 [localPath]，缺失时使用 [filename] + 网络资源。
/// 记录 [scrambleId] 与 [aid] 是因为部分页面需要在线获取，必须携带这些参数。
@immutable
class ChapterPageItem
{
    /// 章节内页码（0-based）
    final int index;

    /// 已下载的本地文件绝对路径（可能为空，表示未下载）
    final String? localPath;

    /// 网络图片文件名（如 "00001.jpg"）；[localPath] 为空时用于网络加载
    final String? filename;

    /// scramble_id；[localPath] 为空时使用
    final int scrambleId;

    /// aid（整数 photoId）；[localPath] 为空时使用
    final int aid;

    const ChapterPageItem({
        required this.index,
        this.localPath,
        this.filename,
        this.scrambleId = 0,
        this.aid = 0,
    });

    /// 本地文件是否可用
    bool get hasLocal => localPath != null && localPath!.isNotEmpty;

    /// 是否需要走网络
    bool get needNetwork => !hasLocal && filename != null && filename!.isNotEmpty;
}
