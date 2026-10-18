import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../common/app_logger.dart';

/// 登录会话（持久化模型）
///
/// 只持久化会话凭据与基本用户信息，不持久化密码。
/// AVS 是禁漫的会话 token（登录响应中的 s 字段），
/// 存储于应用私有支持目录，与项目其它持久化文件同级。
class JmAuthSession
{
    /// 用户 ID
    final String uid;

    /// 用户名
    final String username;

    /// 头像
    final String photo;

    /// AVS 会话 token
    final String avs;

    /// 收藏本子数
    final int albumFavorites;

    /// 保存时间（ISO8601）
    final String savedAt;

    const JmAuthSession({
        required this.uid,
        required this.username,
        required this.avs,
        this.photo = '',
        this.albumFavorites = 0,
        this.savedAt = '',
    });

    Map<String, dynamic> toJson()
    {
        return {
            'uid': uid,
            'username': username,
            'photo': photo,
            'avs': avs,
            'albumFavorites': albumFavorites,
            'savedAt': savedAt,
        };
    }

    factory JmAuthSession.fromJson(Map<String, dynamic> json)
    {
        return JmAuthSession(
            uid: json['uid']?.toString() ?? '',
            username: json['username']?.toString() ?? '',
            photo: json['photo']?.toString() ?? '',
            avs: json['avs']?.toString() ?? '',
            albumFavorites: (json['albumFavorites'] as num?)?.toInt() ?? 0,
            savedAt: json['savedAt']?.toString() ?? '',
        );
    }
}

/// 登录会话持久化（JSON 文件）
///
/// 文件位置：`{appSupportDir}/jm_auth.json`
/// 写入失败不抛异常（记录日志），读取失败返回 null（视为未登录）。
class JmAuthPersistence
{
    static const _fileName = 'jm_auth.json';

    /// 获取存储文件路径
    static Future<String> _getFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}$_fileName';
    }

    /// 读取持久化的会话（不存在或解析失败返回 null）
    static Future<JmAuthSession?> load() async
    {
        try
        {
            final file = File(await _getFilePath());
            if (!await file.exists()) return null;
            final content = await file.readAsString();
            return JmAuthSession.fromJson(jsonDecode(content));
        }
        catch (e)
        {
            appLogger.w('JmAuthPersistence 读取会话失败: $e');
            return null;
        }
    }

    /// 保存会话（写入失败静默忽略）
    static Future<void> save(JmAuthSession session) async
    {
        try
        {
            final file = File(await _getFilePath());
            await file.parent.create(recursive: true);
            await file.writeAsString(
                jsonEncode(session.toJson()),
                flush: true,
            );
        }
        catch (e)
        {
            // 保存失败只影响下次启动的会话恢复，不影响本次登录状态
            appLogger.w('JmAuthPersistence 保存会话失败: $e');
        }
    }

    /// 清除会话（登出）
    static Future<void> clear() async
    {
        try
        {
            final file = File(await _getFilePath());
            if (await file.exists())
            {
                await file.delete();
            }
        }
        catch (e)
        {
            // 忽略删除失败
            appLogger.w('JmAuthPersistence 清除会话失败: $e');
        }
    }
}
