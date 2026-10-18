import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jm/jm_auth_persistence.dart';
import '../core/jm/jm_client.dart';
import 'search_provider.dart';

/// 账号状态
class AuthState
{
    /// 是否已登录
    final bool loggedIn;

    /// 是否正在执行登录/登出操作
    final bool busy;

    /// 用户名
    final String username;

    /// 用户 ID
    final String uid;

    /// AVS 会话 token
    final String avs;

    /// 收藏本子数
    final int albumFavorites;

    /// 最近一次操作的错误信息
    final String? error;

    const AuthState({
        this.loggedIn = false,
        this.busy = false,
        this.username = '',
        this.uid = '',
        this.avs = '',
        this.albumFavorites = 0,
        this.error,
    });

    AuthState copyWith({
        bool? loggedIn,
        bool? busy,
        String? username,
        String? uid,
        String? avs,
        int? albumFavorites,
        String? error,
        bool clearError = false,
    })
    {
        return AuthState(
            loggedIn: loggedIn ?? this.loggedIn,
            busy: busy ?? this.busy,
            username: username ?? this.username,
            uid: uid ?? this.uid,
            avs: avs ?? this.avs,
            albumFavorites: albumFavorites ?? this.albumFavorites,
            error: clearError ? null : (error ?? this.error),
        );
    }
}

/// 账号 Provider
///
/// 构造时监听 [jmClientProvider]：代理等配置变更导致客户端重建时，
/// 本 Provider 跟随重建并从持久化恢复会话（AVS 写入新客户端的 Cookie）。
class AuthNotifier extends StateNotifier<AuthState>
{
    final JmClient _client;

    /// 会话恢复任务（构造时启动，幂等复用同一 Future）
    late final Future<void> _restoreFuture;

    AuthNotifier(this._client) : super(const AuthState())
    {
        _restoreFuture = _restore();
    }

    /// 确保会话恢复已完成（幂等）
    ///
    /// 供收藏等登录敏感操作在判断登录态前调用，
    /// 避免 Provider 刚创建、恢复尚未完成时误判为未登录。
    Future<void> ensureRestored() => _restoreFuture;

    /// 从持久化恢复登录会话（fire-and-forget）
    Future<void> _restore() async
    {
        final session = await JmAuthPersistence.load();
        if (session == null || session.avs.isEmpty) return;

        _client.restoreSession(session.avs);
        if (!mounted) return;
        state = AuthState(
            loggedIn: true,
            username: session.username,
            uid: session.uid,
            avs: session.avs,
            albumFavorites: session.albumFavorites,
        );
    }

    /// 登录
    ///
    /// 成功后持久化会话（不含密码）；业务失败将 message 写入 error。
    Future<bool> login(String username, String password) async
    {
        if (state.busy) return false;
        state = state.copyWith(busy: true, clearError: true);

        try
        {
            final result = await _client.login(username, password);
            if (!result.success)
            {
                state = state.copyWith(
                    busy: false,
                    error: result.message.isEmpty ? '登录失败，请检查账号密码' : result.message,
                );
                return false;
            }

            await JmAuthPersistence.save(JmAuthSession(
                uid: result.uid,
                username: result.username,
                photo: result.photo,
                avs: result.avs,
                albumFavorites: result.albumFavorites,
                savedAt: DateTime.now().toIso8601String(),
            ));

            state = AuthState(
                loggedIn: true,
                username: result.username,
                uid: result.uid,
                avs: result.avs,
                albumFavorites: result.albumFavorites,
            );
            return true;
        }
        catch (e)
        {
            state = state.copyWith(busy: false, error: '登录失败: $e');
            return false;
        }
    }

    /// 退出登录：清除持久化会话并复位状态
    Future<void> logout() async
    {
        await JmAuthPersistence.clear();
        state = const AuthState(loggedIn: false);
    }

    /// 更新本地记录的收藏数量（收藏/取消收藏后同步）
    void updateAlbumFavorites(int count)
    {
        if (!state.loggedIn) return;
        state = state.copyWith(albumFavorites: count);
        // 异步同步到持久化（仅更新收藏数字段）
        JmAuthPersistence.save(JmAuthSession(
            uid: state.uid,
            username: state.username,
            avs: state.avs,
            albumFavorites: count,
            savedAt: DateTime.now().toIso8601String(),
        ));
    }
}

/// 账号 Provider 实例
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref)
{
    final client = ref.watch(jmClientProvider);
    return AuthNotifier(client);
});
