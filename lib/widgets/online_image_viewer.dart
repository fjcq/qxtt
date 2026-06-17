import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/jm/jm_image_loader.dart';
import '../theme/app_colors.dart';

/// 在线阅读单图组件
/// 负责单张图片的加载、显示、重试
/// 支持本地文件优先（如果 [localFilePath] 存在则直接读本地）
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

    /// JmImageLoader 实例
    final JmImageLoader loader;

    const OnlineImageViewer({
        super.key,
        required this.photoId,
        required this.filename,
        required this.scrambleId,
        required this.aid,
        required this.loader,
        this.localFilePath,
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
            // 1. 本地优先——但只有在 .ok 标记存在时才信任本地文件
            // 没有 .ok 标记说明之前下载流程没成功解密（可能是旧 build 残留的加密图）
            if (widget.localFilePath != null &&
                File(widget.localFilePath!).existsSync() &&
                File('${widget.localFilePath!}.ok').existsSync())
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

            // 2. 在线解密
            final result = await widget.loader.loadAndDecode(
                photoId: widget.photoId,
                filename: widget.filename,
                scrambleId: widget.scrambleId,
                aid: widget.aid,
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

    /// 已加载图片（按原比例完整显示，撑满设备宽度）
    /// 关键：用 LayoutBuilder 拿到父容器实际宽度，强制 Image.width = 父容器宽度
    /// 这样 RenderImage._imageSize = (parentWidth, parentWidth * h/w)
    /// layout size 高度 = parentWidth * h/w（按比例），图片高度 = layout 高度（无空白）
    /// 而不是 Image(width: null) 导致 _imageSize=原图尺寸、layout 高度=原图高度（可能比显示高度大很多）
    Widget _buildLoadedImage()
    {
        return LayoutBuilder(
            builder: (context, constraints) {
                return ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                        _bytes!,
                        width: constraints.maxWidth,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) => _buildError(),
                    ),
                );
            },
        );
    }

    /// 加载中
    Widget _buildLoading()
    {
        return Container(
            color: AppColors.background,
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        const CircularProgressIndicator(
                            color: AppColors.accent,
                            strokeWidth: 2,
                        ),
                        const SizedBox(height: 12),
                        Text(
                            _stage.isEmpty ? '加载中...' : _stage,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
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
                                        backgroundColor: AppColors.surfaceVariant,
                                        color: AppColors.accent,
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
            color: AppColors.background,
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        const Icon(
                            Icons.broken_image,
                            color: AppColors.textDisabled,
                            size: 48,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                                _error ?? '加载失败',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                            ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                            icon: const Icon(
                                Icons.refresh,
                                color: AppColors.accent,
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
