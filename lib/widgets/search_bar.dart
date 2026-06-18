import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 搜索栏组件
class AppSearchBar extends StatefulWidget
{
    /// 搜索类型列表
    final List<String> searchTypes;

    /// 当前搜索类型索引
    final int currentTypeIndex;

    /// 搜索回调
    final ValueChanged<String> onSearch;

    /// 搜索类型切换回调
    final ValueChanged<int> onTypeChanged;

    /// 提示文字
    final String hintText;

    const AppSearchBar({
        super.key,
        this.searchTypes = const ['站内', '作者', '标签', '作品', '角色'],
        this.currentTypeIndex = 0,
        required this.onSearch,
        required this.onTypeChanged,
        this.hintText = '搜索漫画...',
    });

    @override
    State<AppSearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<AppSearchBar>
{
    final _controller = TextEditingController();
    final _focusNode = FocusNode();

    @override
    void dispose()
    {
        _controller.dispose();
        _focusNode.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return Column(
            children: [
                // 搜索输入框
                Container(
                    decoration: BoxDecoration(
                        color: context.appColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: _focusNode.hasFocus
                                ? context.appColors.accent
                                : Colors.transparent,
                            width: 2,
                        ),
                    ),
                    child: Row(
                        children: [
                            const SizedBox(width: 16),
                            Icon(
                                Icons.search,
                                color: context.appColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: TextField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    style: TextStyle(
                                        color: context.appColors.textPrimary,
                                        fontSize: 16,
                                    ),
                                    decoration: InputDecoration(
                                        hintText: widget.hintText,
                                        hintStyle: TextStyle(
                                            color: context.appColors.textDisabled,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                        ),
                                    ),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: (value)
                                    {
                                        if (value.trim().isNotEmpty)
                                        {
                                            widget.onSearch(value.trim());
                                        }
                                    },
                                ),
                            ),
                            if (_controller.text.isNotEmpty)
                                IconButton(
                                    icon: Icon(
                                        Icons.clear,
                                        color: context.appColors.textSecondary,
                                        size: 20,
                                    ),
                                    onPressed: ()
                                    {
                                        _controller.clear();
                                        setState(() {});
                                    },
                                ),
                            IconButton(
                                icon: Icon(
                                    Icons.arrow_forward,
                                    color: context.appColors.accent,
                                ),
                                onPressed: ()
                                {
                                    if (_controller.text.trim().isNotEmpty)
                                    {
                                        widget.onSearch(_controller.text.trim());
                                    }
                                },
                            ),
                        ],
                    ),
                ),
                const SizedBox(height: 12),
                // 搜索类型切换
                SizedBox(
                    height: 36,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.searchTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index)
                        {
                            final isSelected = index == widget.currentTypeIndex;
                            return GestureDetector(
                                onTap: () => widget.onTypeChanged(index),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                        color: isSelected
                                            ? context.appColors.accent
                                            : context.appColors.surfaceVariant,
                                        borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                        widget.searchTypes[index],
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? context.appColors.background
                                                : context.appColors.textSecondary,
                                        ),
                                    ),
                                ),
                            );
                        },
                    ),
                ),
            ],
        );
    }
}
