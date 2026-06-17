import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_entity.dart';
import '../core/jm/jm_image_loader.dart';
import '../providers/browse_history_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../utils/path_helper.dart';
import '../widgets/online_image_viewer.dart';

/// 在线阅读器页
/// 流程:
/// 1. 获取 photo_detail + scramble_id
/// 2. 加载时优先尝试本地文件（如果整本已下载）
/// 3. 否则在线下载→解密→内存渲染
/// 4. 预加载当前页前后各 2 张
/// 5. 退出时保存阅读进度到 browse_history
class OnlineReaderPage extends ConsumerStatefulWidget
{
    /// 章节 ID
    final String photoId;

    const OnlineReaderPage({
        super.key,
        required this.photoId,
    });

    @override
    ConsumerState<OnlineReaderPage> createState() => _OnlineReaderPageState();
}

class _OnlineReaderPageState extends ConsumerState<OnlineReaderPage>
{
    /// 章节详情
    PhotoDetail? _photoDetail;

    /// 本子详情（用于本地文件查找）
    AlbumDetail? _albumDetail;

    /// scramble_id
    int _scrambleId = 0;

    /// 当前页
    int _currentPage = 0;

    /// 显示控制栏
    bool _showControls = true;

    /// 错误信息
    String? _error;

    /// 当前是否正在初始加载
    bool _initialLoading = true;

    /// 本子下载根目录（探测一次）
    String? _downloadRoot;

    @override
    void initState()
    {
        super.initState();
        _loadInitial();
    }

    /// 初始加载章节信息和本地文件探测
    Future<void> _loadInitial() async
    {
        final client = ref.read(jmClientProvider);

        // 探测本地下载根目录
        try
        {
            _downloadRoot = await PathHelper.getDownloadDir();
        }
        catch (_)
        {
            _downloadRoot = null;
        }

        // 查询历史进度（用于恢复 lastReadPage）
        int startPage = 0;
        try
        {
            final history = await ref.read(browseHistoryDaoProvider).getAllHistory();
            // 由于 getHistory 是按 albumId 查的，但当前页还不知道 albumId，
            // 先简单：尝试每个历史，看其 lastReadPhotoId == widget.photoId
            for (final h in history)
            {
                if (h.lastReadPhotoId == widget.photoId)
                {
                    startPage = h.lastReadPage;
                    break;
                }
            }
        }
        catch (_)
        {
            // 忽略
        }

        try
        {
            final detail = await client.getPhotoDetail(widget.photoId);
            final scrambleId = await client.getScrambleId(widget.photoId);

            // 尝试获取本子详情（用于按 albumTitle/episodeIndex 查找本地文件）
            // 本子详情获取失败不影响阅读，仅影响本地文件命中率
            AlbumDetail? albumDetail;
            try
            {
                albumDetail = await client.getAlbumDetail(detail.albumId);
            }
            catch (_)
            {
                albumDetail = null;
            }

            if (!mounted) return;
            setState(()
            {
                _photoDetail = detail;
                _albumDetail = albumDetail;
                _scrambleId = scrambleId;
                _currentPage = startPage.clamp(0, detail.pageArr.isEmpty ? 0 : detail.pageArr.length - 1);
                _initialLoading = false;
            });
        }
        catch (e)
        {
            if (!mounted) return;
            setState(()
            {
                _error = e.toString();
                _initialLoading = false;
            });
        }
    }

    /// 切换到指定页
    void _setPage(int page)
    {
        if (_photoDetail == null) return;
        final max = _photoDetail!.pageArr.length - 1;
        if (page < 0 || page > max) return;
        setState(()
        {
            _currentPage = page;
        });
        _persistProgress();
    }

    /// 持久化阅读进度
    Future<void> _persistProgress() async
    {
        if (_photoDetail == null) return;
        try
        {
            await ref.read(browseHistoryDaoProvider).updateReadProgress(
                _photoDetail!.albumId,
                _currentPage,
                widget.photoId,
            );
        }
        catch (_)
        {
            // 忽略持久化失败
        }
    }

    /// 计算本地文件路径（如果已下载整本）
    /// 下载约定: ${downloadDir}/{albumTitle}/{episodeIndex}/{00001.jpg, ...}
    /// 查找策略:
    /// 1) 单章下载: ${downloadRoot}/${photoId}/{seq}.jpg
    /// 2) 整本下载: ${downloadRoot}/${albumTitle}/${episodeIndex}/{seq}.jpg
    /// 3) 退化: 扫描 downloadRoot 找包含 photoId 路径的同名序列（兼容旧版本下载）
    String? _findLocalPath(int pageIndex)
    {
        if (_photoDetail == null || _downloadRoot == null) return null;
        final seq = (pageIndex + 1).toString().padLeft(5, '0');
        final sep = Platform.pathSeparator;

        // 1) 单章下载目录: ${downloadRoot}/${photoId}/{seq}.jpg
        // 必须有 .ok 标记才视为"已解密"——旧 build 残留的加密图会逃过此判断
        final photoDirPath = '$_downloadRoot$sep${widget.photoId}$sep$seq.jpg';
        if (File(photoDirPath).existsSync() &&
            File('$photoDirPath.ok').existsSync())
        {
            return photoDirPath;
        }

        // 2) 整本下载: 需要 albumTitle + episodeIndex
        if (_albumDetail != null)
        {
            final episode = _findEpisodeInAlbum(widget.photoId);
            if (episode != null)
            {
                final albumPath = PathHelper.getPagePath(
                    _downloadRoot!,
                    _albumDetail!.name,
                    episode.index,
                    pageIndex,
                );
                if (File(albumPath).existsSync() &&
                    File('$albumPath.ok').existsSync())
                {
                    return albumPath;
                }
            }
        }

        // 3) 退化: 扫描 downloadRoot 找包含 photoId 路径的同名序列
        // 出于保守，仅在明确包含 photoId 时才返回，避免误命中
        try
        {
            final root = Directory(_downloadRoot!);
            if (!root.existsSync()) return null;
            for (final entity in root.listSync(recursive: true))
            {
                if (entity is File &&
                    entity.path.endsWith('$seq.jpg') &&
                    entity.path.contains(widget.photoId))
                {
                    return entity.path;
                }
            }
            return null;
        }
        catch (_)
        {
            return null;
        }
    }

    /// 在 albumDetail.episodes 中查找 photoId 对应的章节
    Episode? _findEpisodeInAlbum(String photoId)
    {
        if (_albumDetail == null) return null;
        for (final ep in _albumDetail!.episodes)
        {
            if (ep.photoId == photoId)
            {
                return ep;
            }
        }
        return null;
    }

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            backgroundColor: Colors.black,
            body: GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Stack(
                    children: [
                        _buildContent(),
                        if (_showControls && !_initialLoading && _error == null)
                            _buildControls(),
                    ],
                ),
            ),
        );
    }

    Widget _buildContent()
    {
        if (_initialLoading)
        {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
            );
        }
        if (_error != null)
        {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                                _error!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: ()
                                {
                                    setState(()
                                    {
                                        _initialLoading = true;
                                        _error = null;
                                    });
                                    _loadInitial();
                                },
                                child: const Text('重试'),
                            ),
                        ],
                    ),
                ),
            );
        }
        if (_photoDetail == null || _photoDetail!.pageArr.isEmpty)
        {
            return const Center(
                child: Text(
                    '暂无图片',
                    style: TextStyle(color: AppColors.textSecondary),
                ),
            );
        }

        // 仅支持纵向滚动模式
        final pages = _photoDetail!.pageArr;
        return _buildVerticalScroll(pages);
    }

    /// 构造单图 Widget（带预加载和本地优先）
    Widget _buildImageForIndex(int index, List<String> pages)
    {
        final client = ref.watch(jmClientProvider);
        final loader = JmImageLoader(client);
        // aid 必须是 photoId（章节ID），与 Python 参考实现中
        // parse_to_jm_id(url) 从 /media/photos/{photoId}/{filename} 提取的 ID 一致
        final aid = int.tryParse(widget.photoId) ?? 0;
        final localPath = _findLocalPath(index);

        return OnlineImageViewer(
            // 使用 key+ValueKey 强制重建以响应切换
            key: ValueKey('${widget.photoId}_$index'),
            photoId: widget.photoId,
            filename: pages[index],
            scrambleId: _scrambleId,
            aid: aid,
            loader: loader,
            localFilePath: localPath,
        );
    }

    /// 纵向滚动
    Widget _buildVerticalScroll(List<String> pages)
    {
        // 使用可见窗口（前后预加载）渲染，离屏则不构建 → 用 ListView.builder
        return ListView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index)
            {
                return _buildImageForIndex(index, pages);
            },
        );
    }

    Widget _buildControls()
    {
        final total = _photoDetail?.pageArr.length ?? 0;
        return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                // 顶部
                Container(
                    padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 16,
                        right: 16,
                        bottom: 8,
                    ),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                        ),
                    ),
                    child: Row(
                        children: [
                            IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () async
                                {
                                    await _persistProgress();
                                    if (mounted) Navigator.of(context).pop();
                                },
                            ),
                            Expanded(
                                child: Text(
                                    '${_currentPage + 1} / $total',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                    ),
                                ),
                            ),
                        ],
                    ),
                ),
                // 底部
                Container(
                    padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black54, Colors.transparent],
                        ),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            IconButton(
                                icon: const Icon(Icons.skip_previous, color: Colors.white),
                                onPressed: _currentPage > 0
                                    ? () => _setPage(_currentPage - 1)
                                    : null,
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                                icon: const Icon(Icons.skip_next, color: Colors.white),
                                onPressed: _currentPage < total - 1
                                    ? () => _setPage(_currentPage + 1)
                                    : null,
                            ),
                        ],
                    ),
                ),
            ],
        );
    }
}
