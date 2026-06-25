import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/reader/reader_download_engine.dart';
import '../core/reader/reader_image_loader.dart';
import '../theme/app_colors.dart';
import '../utils/chapter_complete_helper.dart';
import '../utils/file_helper.dart';

/// 在线阅读单图组件
/// 负责单张图片的加载、显示、重试
/// 加载优先级：
///   1. 已下载的本地文件（章节级 `.complete` 标记或单页 `.ok` 标记）
///   2. 阅读本地缓存
///   3. 临时解密缓存
///   4. 网络下载（多线程引擎）
class OnlineImageViewer extends StatefulWidget
{
    /// 章节 ID
    final String photoId;

    /// 图片文件名
    final String filename;

    /// scramble_id
    final int scrambleId;

    /// 本子 ID（整数）
    final int aid;

    /// 本地文件路径（可选；存在则优先读本地）
    final String? localFilePath;

    /// 阅读图片加载器
    final ReaderImageLoader loader;

    /// 下载优先级
    final DownloadPriority priority;

    /// 全局缩放比例（默认1.0，由阅读器传入）
    final double scale;

    const OnlineImageViewer({
        super.key,
        required this.photoId,
        required this.filename,
        required this.scrambleId,
        required this.aid,
        required this.loader,
        this.localFilePath,
        this.priority = DownloadPriority.background,
        this.scale = 1.0,
    });

    @override
    State<OnlineImageViewer> createState() => _OnlineImageViewerState();
}

class _OnlineImageViewerState extends State<OnlineImageViewer>
{
    /// 已加载的图片字节
    Uint8List? _bytes;

    /// 加载进度 0.0 ~ 1.0
    double _progress = 0.0;

    /// 阶段描述
    String _stage = '';

    /// 错误信息
    String? _error;

    /// 是否正在加载
    bool _loading = false;

    @override
    void initState()
    {
        super.initState();
        _startLoad();
    }

    @override
    void didUpdateWidget(covariant OnlineImageViewer oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        // photoId 或 filename 变化时重新加载
        if (oldWidget.photoId != widget.photoId ||
            oldWidget.filename != widget.filename)
        {
            _bytes = null;
            _error = null;
            _progress = 0.0;
            _startLoad();
        }
    }

    @override
    void dispose()
    {
        // 离开视口时取消低优先级下载，避免浪费带宽
        if (widget.priority != DownloadPriority.immediate)
        {
            widget.loader.cancel(widget.photoId, widget.filename);
        }
        super.dispose();
    }

    /// 启动加载流程
    Future<void> _startLoad() async
    {
        if (_loading) return;
        setState(()
        {
            _loading = true;
            _error = null;
            _progress = 0.0;
            _stage = '准备中';
        });

        try
        {
            // 1. 已下载的本地文件优先
            // 【性能优化 P2】优先检查章节级 `.complete`，存在则整章有效；
            // 否则回退到单页 `.ok` 检查（兼容边下边看场景）
            // 走 FileExistenceCache 5s 缓存，避免高频 existsSync 阻塞 UI
            if (widget.localFilePath != null &&
                await _isLocalReady(widget.localFilePath!))
            {
                setState(() => _stage = '本地');
                final localFile = File(widget.localFilePath!);
                final data = await localFile.readAsBytes();
                if (!mounted) return;
                setState(()
                {
                    _bytes = data;
                    _progress = 1.0;
                    _stage = '本地';
                    _loading = false;
                });
                return;
            }

            // 2. 走统一阅读图片加载器（临时缓存 / 网络）
            final result = await widget.loader.load(
                photoId: widget.photoId,
                filename: widget.filename,
                scrambleId: widget.scrambleId,
                aid: widget.aid,
                priority: widget.priority,
                onProgress: (p)
                {
                    if (mounted)
                    {
                        setState(()
                        {
                            _progress = p.progress;
                            _stage = p.stage;
                        });
                    }
                },
            );

            if (!mounted) return;
            setState(()
            {
                _bytes = result.bytes;
                _stage = _sourceText(result.source);
                _progress = 1.0;
                _loading = false;
            });
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

    /// 根据图片来源返回显示文本
    String _sourceText(ReaderImageSource source)
    {
        switch (source)
        {
            case ReaderImageSource.memory:
                return '内存';
            case ReaderImageSource.decodedCache:
                return '缓存';
            case ReaderImageSource.network:
                return '网络';
        }
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
        return _buildLoading();
    }

    /// 已加载图片（按原比例完整显示，撑满设备宽度 × scale）
    /// scale > 1 时图片放大，允许横向滚动查看；scale < 1 时图片缩小
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

    /// 加载中
    Widget _buildLoading()
    {
        return Container(
            color: context.appColors.background,
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        CircularProgressIndicator(
                            color: context.appColors.accent,
                            strokeWidth: 2,
                        ),
                        const SizedBox(height: 12),
                        Text(
                            _stage.isEmpty ? '加载中...' : _stage,
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 12,
                            ),
                        ),
                        if (_progress > 0)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                    width: 160,
                                    child: LinearProgressIndicator(
                                        value: _progress,
                                        backgroundColor: context.appColors.surfaceVariant,
                                        color: context.appColors.accent,
                                        minHeight: 2,
                                    ),
                                ),
                            ),
                    ],
                ),
            ),
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
