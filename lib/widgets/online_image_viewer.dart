import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/download_provider.dart';
import '../theme/app_colors.dart';
import '../utils/chapter_complete_helper.dart';
import '../utils/file_helper.dart';
import 'waiting_page_placeholder.dart';

/// 在线阅读单图组件（统一阅读架构）
///
/// 【统一阅读架构】
/// 阅读器只读本地文件，本组件不再走网络下载回退：
/// - 本地命中（`.complete` 整章或 `.ok` 单页）→ 读取本地文件字节渲染
/// - 本地未命中 → 显示 [WaitingPagePlaceholder]，订阅 [DownloadService.onProgress]
///   当对应 photoId + filename 的单页完成事件到达时自动切换为本地图
///
/// 父级（在线阅读页）负责调用 [DownloadService.ensureChapterDownloaded]
/// 创建/复用章节下载任务，本组件仅消费下载结果。
class OnlineImageViewer extends ConsumerStatefulWidget
{
    /// 章节 ID
    final String photoId;

    /// 图片文件名
    final String filename;

    /// 章节 0-based 页码（用于占位组件显示）
    final int pageIndex;

    /// 章节总页数（用于占位组件显示进度）
    final int totalPages;

    /// 本地文件路径（章节保存目录 + filename）
    final String localFilePath;

    /// 全局缩放比例（默认 1.0，由阅读器传入）
    final double scale;

    const OnlineImageViewer({
        super.key,
        required this.photoId,
        required this.filename,
        required this.localFilePath,
        required this.pageIndex,
        this.totalPages = 0,
        this.scale = 1.0,
    });

    @override
    ConsumerState<OnlineImageViewer> createState() => _OnlineImageViewerState();
}

class _OnlineImageViewerState extends ConsumerState<OnlineImageViewer>
{
    /// 已加载的本地图片字节
    Uint8List? _bytes;

    /// 加载错误信息
    String? _error;

    /// 是否正在加载
    bool _loading = false;

    /// 下载进度订阅
    StreamSubscription<dynamic>? _progressSub;

    /// 占位组件当前展示的章节进度
    double? _placeholderProgress;

    /// 占位组件当前已下载页数
    int _placeholderCurrent = 0;

    /// 占位组件当前总页数
    int _placeholderTotal = 0;

    @override
    void initState()
    {
        super.initState();
        _startLoad();
        _subscribeProgress();
    }

    @override
    void didUpdateWidget(covariant OnlineImageViewer oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        // photoId 或 filename 变化时重新加载
        if (oldWidget.photoId != widget.photoId ||
            oldWidget.filename != widget.filename ||
            oldWidget.localFilePath != widget.localFilePath)
        {
            _bytes = null;
            _error = null;
            _loading = false;
            _placeholderProgress = null;
            _placeholderCurrent = 0;
            _placeholderTotal = 0;
            _startLoad();
        }
    }

    @override
    void dispose()
    {
        _progressSub?.cancel();
        super.dispose();
    }

    /// 订阅下载进度事件
    ///
    /// 过滤当前 photoId 的单页完成事件，触发本地文件重读；
    /// 同时维持章节整体进度供占位组件显示。
    void _subscribeProgress()
    {
        _progressSub?.cancel();
        final downloadService = ref.read(downloadServiceProvider);
        _progressSub = downloadService.onProgress
            .where((e) => e.photoId == widget.photoId)
            .listen((e) {
                if (!mounted) return;
                if (e.completedFilename == widget.filename)
                {
                    // 当前页下载完成：失效缓存后重读本地
                    FileExistenceCache.invalidate(widget.localFilePath);
                    FileExistenceCache.invalidate('${widget.localFilePath}.ok');
                    _startLoad();
                }
                else if (e.status == 'running' || e.status == 'pageCompleted')
                {
                    setState(() {
                        _placeholderCurrent = e.current;
                        _placeholderTotal = e.total;
                        _placeholderProgress = e.progress;
                    });
                }
                else if (e.status == 'completed')
                {
                    setState(() {
                        _placeholderCurrent = e.total;
                        _placeholderTotal = e.total;
                        _placeholderProgress = 1.0;
                    });
                    // 章节完成事件也可能携带当前页就绪信号，尝试重读
                    if (_bytes == null)
                    {
                        FileExistenceCache.invalidate(widget.localFilePath);
                        _startLoad();
                    }
                }
            });
    }

    /// 启动加载流程
    ///
    /// 流程：
    /// 1. 检查本地文件是否就绪（章节级 `.complete` 或单页 `.ok`）
    /// 2. 命中 → 读取本地字节并渲染
    /// 3. 未命中 → 保持占位状态，等待下载事件触发自动刷新
    Future<void> _startLoad() async
    {
        if (_loading) return;
        setState(()
        {
            _loading = true;
            _error = null;
        });

        try
        {
            if (await _isLocalReady(widget.localFilePath))
            {
                final localFile = File(widget.localFilePath);
                final data = await localFile.readAsBytes();
                if (!mounted) return;
                setState(()
                {
                    _bytes = data;
                    _loading = false;
                });
                return;
            }

            // 本地未就绪：保持占位状态，等待下载事件
            if (!mounted) return;
            setState(() => _loading = false);
        }
        catch (e)
        {
            if (!mounted) return;
            setState(()
            {
                _error = e.toString();
                _loading = false;
            });
        }
    }

    /// 判断本地文件是否就绪可读
    ///
    /// 【性能优化 P2】
    /// - 优先检查章节级 `.complete`：存在则整章有效，仅需 .jpg 存在即可
    /// - 回退到单页 `.ok` 检查（兼容边下边看场景）
    Future<bool> _isLocalReady(String localFilePath) async
    {
        if (localFilePath.isEmpty) return false;
        // 1. 章节级 .complete 命中 → 整章有效
        final sep = Platform.pathSeparator;
        final lastSep = localFilePath.lastIndexOf(sep);
        if (lastSep > 0)
        {
            final chapterDir = localFilePath.substring(0, lastSep);
            if (await ChapterCompleteHelper.isChapterComplete(chapterDir))
            {
                return await FileExistenceCache.fileExists(localFilePath);
            }
        }
        // 2. 回退到单页 .ok 检查
        final saveExists = await FileExistenceCache.fileExists(localFilePath);
        if (!saveExists) return false;
        return await FileExistenceCache.fileExists('$localFilePath.ok');
    }

    @override
    Widget build(BuildContext context)
    {
        if (_bytes != null)
        {
            return _buildLoadedImage();
        }
        if (_error != null)
        {
            return _buildError();
        }
        return _buildWaiting();
    }

    /// 已加载图片（按原比例完整显示，撑满设备宽度 × scale）
    Widget _buildLoadedImage()
    {
        return LayoutBuilder(
            builder: (context, constraints)
            {
                final displayWidth = constraints.maxWidth * widget.scale;
                return ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                        _bytes!,
                        width: displayWidth,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) => _buildError(),
                    ),
                );
            },
        );
    }

    /// 未下载页占位组件
    Widget _buildWaiting()
    {
        return WaitingPagePlaceholder(
            key: ValueKey('${widget.photoId}_${widget.filename}_waiting'),
            pageIndex: widget.pageIndex,
            progress: _placeholderProgress,
            current: _placeholderCurrent,
            total: _placeholderTotal > 0
                ? _placeholderTotal
                : widget.totalPages,
        );
    }

    /// 错误占位
    Widget _buildError()
    {
        return Container(
            color: context.appColors.background,
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(
                            Icons.broken_image,
                            color: context.appColors.textDisabled,
                            size: 48,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                                _error ?? '加载失败',
                                style: TextStyle(
                                    color: context.appColors.textSecondary,
                                    fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                            ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                            icon: Icon(
                                Icons.refresh,
                                color: context.appColors.accent,
                                size: 18,
                            ),
                            label: const Text('重试'),
                            onPressed: ()
                            {
                                _bytes = null;
                                _error = null;
                                _startLoad();
                            },
                        ),
                    ],
                ),
            ),
        );
    }
}
