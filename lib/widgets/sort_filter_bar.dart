import 'package:flutter/material.dart';

import '../providers/library_provider.dart';
import '../theme/app_colors.dart';

/// 已下载分页的排序 + 搜索条
class SortFilterBar extends StatelessWidget
{
    /// 排序方式
    final LibrarySortType sortType;

    /// 排序变更回调
    final ValueChanged<LibrarySortType> onSortChanged;

    /// 搜索关键字
    final String keyword;

    /// 搜索变更回调
    final ValueChanged<String> onKeywordChanged;

    /// 触发进入编辑模式
    final VoidCallback? onEnterEditMode;

    /// 是否正在编辑模式
    final bool isEditing;

    const SortFilterBar({
        super.key,
        required this.sortType,
        required this.onSortChanged,
        required this.keyword,
        required this.onKeywordChanged,
        this.onEnterEditMode,
        this.isEditing = false,
    });

    @override
    Widget build(BuildContext context)
    {
        return Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
                children: [
                    // 排序按钮
                    _SortChip(
                        current: sortType,
                        onSelected: onSortChanged,
                    ),
                    const SizedBox(width: 8),
                    // 搜索框
                    Expanded(
                        child: _SearchField(
                            keyword: keyword,
                            onChanged: onKeywordChanged,
                        ),
                    ),
                    if (onEnterEditMode != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                            tooltip: isEditing ? '退出编辑' : '管理',
                            onPressed: onEnterEditMode,
                            icon: Icon(
                                isEditing
                                    ? Icons.close
                                    : Icons.checklist_rtl,
                                color: isEditing
                                    ? context.appColors.accent
                                    : context.appColors.textSecondary,
                            ),
                        ),
                    ],
                ],
            ),
        );
    }
}

/// 排序选择按钮
class _SortChip extends StatelessWidget
{
    final LibrarySortType current;
    final ValueChanged<LibrarySortType> onSelected;

    const _SortChip({required this.current, required this.onSelected});

    @override
    Widget build(BuildContext context)
    {
        return PopupMenuButton<LibrarySortType>(
            tooltip: '排序',
            position: PopupMenuPosition.under,
            onSelected: onSelected,
            color: context.appColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: context.appColors.divider.withValues(alpha: 0.6),
                ),
            ),
            itemBuilder: (context)
            {
                return LibrarySortType.values.map((type)
                {
                    return PopupMenuItem<LibrarySortType>(
                        value: type,
                        child: Row(
                            children: [
                                Icon(
                                    current == type
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: current == type
                                        ? context.appColors.accent
                                        : context.appColors.textDisabled,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                    type.label,
                                    style: TextStyle(
                                        color: current == type
                                            ? context.appColors.textPrimary
                                            : context.appColors.textSecondary,
                                    ),
                                ),
                            ],
                        ),
                    );
                }).toList();
            },
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: context.appColors.divider.withValues(alpha: 0.6),
                    ),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                            Icons.sort,
                            size: 16,
                            color: context.appColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                            current.label,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.appColors.textPrimary,
                            ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: context.appColors.textSecondary,
                        ),
                    ],
                ),
            ),
        );
    }
}

/// 搜索输入框
class _SearchField extends StatefulWidget
{
    final String keyword;
    final ValueChanged<String> onChanged;

    const _SearchField({required this.keyword, required this.onChanged});

    @override
    State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField>
{
    late final TextEditingController _controller;

    @override
    void initState()
    {
        super.initState();
        _controller = TextEditingController(text: widget.keyword);
    }

    @override
    void didUpdateWidget(covariant _SearchField oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        // 外部清空时同步控制器（编辑模式退出时）
        if (widget.keyword != _controller.text)
        {
            _controller.text = widget.keyword;
            _controller.selection = TextSelection.collapsed(
                offset: widget.keyword.length,
            );
        }
    }

    @override
    void dispose()
    {
        _controller.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return Container(
            height: 40,
            decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.appColors.divider.withValues(alpha: 0.6),
                ),
            ),
            child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textPrimary,
                ),
                decoration: InputDecoration(
                    hintText: '搜索标题/作者',
                    hintStyle: TextStyle(
                        fontSize: 13,
                        color: context.appColors.textDisabled,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: InputBorder.none,
                    prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: context.appColors.textDisabled,
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            splashRadius: 18,
                            icon: Icon(
                                Icons.close,
                                size: 16,
                                color: context.appColors.textDisabled,
                            ),
                            onPressed: ()
                            {
                                _controller.clear();
                                widget.onChanged('');
                            },
                        ),
                ),
            ),
        );
    }
}
