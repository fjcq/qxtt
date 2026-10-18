import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/favorite_provider.dart';
import '../theme/app_colors.dart';

/// 详情页收藏按钮
///
/// 服务端收藏接口为 Toggle 语义（已收藏则取消，未收藏则添加），
/// 本按钮以局部状态跟踪最近一次操作结果：实心=已收藏，空心=未收藏/未知。
/// 未登录时点击引导去设置页登录。
class AlbumDetailFavoriteButton extends ConsumerStatefulWidget
{
    /// 本子 ID
    final String albumId;

    /// 初始收藏状态（来自详情接口 is_favorite）
    final bool initiallyFavorite;

    const AlbumDetailFavoriteButton({
        super.key,
        required this.albumId,
        this.initiallyFavorite = false,
    });

    @override
    ConsumerState<AlbumDetailFavoriteButton> createState() =>
        _AlbumDetailFavoriteButtonState();
}

class _AlbumDetailFavoriteButtonState
    extends ConsumerState<AlbumDetailFavoriteButton>
{
    /// 收藏状态：null=未知，true=已收藏，false=未收藏
    bool? _favActive;

    /// 是否正在请求
    bool _busy = false;

    @override
    void initState()
    {
        super.initState();
        // 用详情接口返回的 is_favorite 作为初始收藏状态
        _favActive = widget.initiallyFavorite;
    }

    /// 切换收藏状态
    Future<void> _toggle() async
    {
        if (_busy) return;

        // 未登录引导：先确保启动时的会话恢复已完成（幂等），再判断登录态
        if (!ref.read(authProvider).loggedIn)
        {
            await ref.read(authProvider.notifier).ensureRestored();
        }
        if (!mounted) return;
        if (!ref.read(authProvider).loggedIn)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先在设置页登录账号后再收藏')),
            );
            return;
        }

        setState(() => _busy = true);
        try
        {
            final type = await ref
                .read(favoriteProvider.notifier)
                .toggle(widget.albumId);
            if (!mounted) return;
            setState(()
            {
                _favActive = type == 'add';
                _busy = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(type == 'add' ? '已加入收藏' : '已取消收藏'),
                ),
            );
        }
        catch (e)
        {
            if (!mounted) return;
            setState(() => _busy = false);
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('收藏操作失败: $e')),
            );
        }
    }

    @override
    Widget build(BuildContext context)
    {
        return IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(_favActive == true
                    ? Icons.favorite
                    : Icons.favorite_border),
            color: _favActive == true ? context.appColors.error : null,
            tooltip: '收藏',
            onPressed: _toggle,
        );
    }
}
