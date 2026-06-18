import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reader/reader_album_rebuild_mixin.dart';
import 'reader/reader_base_mixin.dart';
import 'reader/reader_chapter_mixin.dart';
import 'reader/reader_content_mixin.dart';
import 'reader/reader_gesture_mixin.dart';
import 'reader/reader_ui_mixin.dart';

/// 离线阅读器页
///
/// 组合 [ReaderBaseMixin]、[ReaderGestureMixin]、[ReaderUIMixin]、
/// [ReaderChapterMixin] 与 [ReaderContentMixin] 实现本地漫画阅读。
/// - PC 端鼠标拖动 + 惯性滑动
/// - 键盘方向键控制（上下翻页，左右切换章节）
/// - 移动端双指缩放
/// - 左右滑动手势切换章节
/// - 进度条、章节导航、目录
class ReaderPage extends ConsumerStatefulWidget {
    /// 章节 ID
    final String photoId;

    const ReaderPage({
        super.key,
        required this.photoId,
    });

    @override
    ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with
        TickerProviderStateMixin<ReaderPage>,
        ReaderBaseMixin<ReaderPage>,
        ReaderGestureMixin<ReaderPage>,
        ReaderUIMixin<ReaderPage>,
        ReaderAlbumRebuildMixin<ReaderPage>,
        ReaderChapterMixin<ReaderPage>,
        ReaderContentMixin<ReaderPage>
{
    @override
    String get initialPhotoId => widget.photoId;

    @override
    Future<void> onClose() async => Navigator.of(context).pop();
}
