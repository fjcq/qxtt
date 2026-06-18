import 'package:flutter/material.dart';

import '../core/jm/jm_entity.dart';
import '../theme/app_colors.dart';

/// 章节目录抽屉组件
/// 供在线阅读器和本地阅读器共用，保证两种模式下目录展示样式一致。
/// 功能：
/// - 展示所有章节标题及序号
/// - 视觉高亮当前阅读章节
/// - 章节数 > 20 时支持搜索过滤
/// - 点击目录项直接跳转
class ChapterCatalogDrawer extends StatefulWidget
{
    /// 章节列表
    final List<Episode> episodes;

    /// 当前章节 photoId
    final String currentPhotoId;

    /// 点击章节回调
    final void Function(Episode episode) onChapterSelected;

    const ChapterCatalogDrawer({
        super.key,
        required this.episodes,
        required this.currentPhotoId,
        required this.onChapterSelected,
    });

    @override
    State<ChapterCatalogDrawer> createState() => _ChapterCatalogDrawerState();
}

class _ChapterCatalogDrawerState extends State<ChapterCatalogDrawer>
{
    /// 搜索关键词
    String _searchQuery = '';

    /// 滚动控制器
    final ScrollController _scrollController = ScrollController();

    /// 是否需要搜索框（章节数 > 20）
    bool get _needSearch => widget.episodes.length > 20;

    /// 当前章节索引
    int get _currentIndex
    {
        for (var i = 0; i < widget.episodes.length; i++)
        {
            if (widget.episodes[i].photoId == widget.currentPhotoId)
            {
                return i;
            }
        }
        return -1;
    }

    /// 过滤后的章节列表
    List<Episode> get _filteredEpisodes
    {
        if (_searchQuery.isEmpty) return widget.episodes;
        final query = _searchQuery.toLowerCase();
        return widget.episodes.where((ep)
        {
            return ep.name.toLowerCase().contains(query) ||
                ep.index.toLowerCase().contains(query);
        }).toList();
    }

    @override
    void initState()
    {
        super.initState();
        // 初始化后自动滚动到当前章节
        WidgetsBinding.instance.addPostFrameCallback((_)
        {
            _scrollToCurrentChapter();
        });
    }

    @override
    void dispose()
    {
        _scrollController.dispose();
        super.dispose();
    }

    /// 滚动到当前章节位置
    void _scrollToCurrentChapter()
    {
        final idx = _currentIndex;
        if (idx < 0 || !_scrollController.hasClients) return;

        // 每个 ListTile 大约 56 像素
        final targetOffset = (idx * 56.0)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(targetOffset);
    }

    @override
    Widget build(BuildContext context)
    {
        final filtered = _filteredEpisodes;
        final currentIdx = _currentIndex;

        return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    _buildDragHandle(),
                    _buildHeader(),
                    if (_needSearch) _buildSearchBar(),
                    const Divider(color: AppColors.divider, height: 1),
                    Flexible(
                        child: filtered.isEmpty
                            ? _buildEmptyHint()
                            : _buildChapterList(filtered, currentIdx),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
            ),
        );
    }

    /// 构建顶部拖拽条
    Widget _buildDragHandle()
    {
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                ),
            ),
        );
    }

    /// 构建标题栏
    Widget _buildHeader()
    {
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
                children: [
                    const Text(
                        '章节目录',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                        ),
                    ),
                    const Spacer(),
                    Text(
                        '共 ${widget.episodes.length} 章',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                        ),
                    ),
                ],
            ),
        );
    }

    /// 构建搜索栏
    Widget _buildSearchBar()
    {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                ),
                decoration: InputDecoration(
                    hintText: '搜索章节...',
                    hintStyle: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textDisabled,
                        size: 20,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                    ),
                    isDense: true,
                ),
                onChanged: (value)
                {
                    setState(() => _searchQuery = value);
                },
            ),
        );
    }

    /// 构建空提示
    Widget _buildEmptyHint()
    {
        return const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
                '未找到匹配的章节',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                ),
            ),
        );
    }

    /// 构建章节列表
    Widget _buildChapterList(List<Episode> episodes, int currentIdx)
    {
        return ListView.builder(
            controller: _scrollController,
            shrinkWrap: true,
            itemCount: episodes.length,
            itemBuilder: (context, index)
            {
                final ep = episodes[index];
                final isCurrent = ep.photoId == widget.currentPhotoId;
                return _buildChapterItem(ep, isCurrent, currentIdx);
            },
        );
    }

    /// 构建单个章节项
    Widget _buildChapterItem(Episode episode, bool isCurrent, int currentIdx)
    {
        return Material(
            color: isCurrent
                ? AppColors.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            child: InkWell(
                onTap: ()
                {
                    Navigator.of(context).pop();
                    if (!isCurrent)
                    {
                        widget.onChapterSelected(episode);
                    }
                },
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                    ),
                    child: Row(
                        children: [
                            // 序号圆圈
                            _buildIndexAvatar(episode, isCurrent),
                            const SizedBox(width: 12),
                            // 章节标题
                            Expanded(
                                child: Text(
                                    episode.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: isCurrent
                                            ? AppColors.accent
                                            : AppColors.textPrimary,
                                        fontWeight: isCurrent
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                    ),
                                ),
                            ),
                            // 当前章节标记
                            if (isCurrent)
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                        '当前',
                                        style: TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                        ),
                                    ),
                                ),
                        ],
                    ),
                ),
            ),
        );
    }

    /// 构建序号圆圈
    Widget _buildIndexAvatar(Episode episode, bool isCurrent)
    {
        return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? AppColors.accent
                    : AppColors.surfaceVariant,
                border: isCurrent
                    ? null
                    : Border.all(color: AppColors.divider, width: 1),
            ),
            child: Center(
                child: Text(
                    episode.index,
                    style: TextStyle(
                        fontSize: 12,
                        color: isCurrent
                            ? Colors.black
                            : AppColors.textPrimary,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                    ),
                ),
            ),
        );
    }
}
