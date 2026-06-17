import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 持久化结果：用户保存的 API/图片域名
class JmDomainConfig
{
    final List<String>? imageDomains;
    final List<String>? apiDomains;
    final DateTime? updatedAt;

    const JmDomainConfig({
        this.imageDomains,
        this.apiDomains,
        this.updatedAt,
    });

    bool get hasImage => imageDomains != null && imageDomains!.isNotEmpty;
    bool get hasApi => apiDomains != null && apiDomains!.isNotEmpty;
    bool get isEmpty => !hasImage && !hasApi;
}

/// 域名持久化服务
/// 用 JSON 文件存储在 <app_docs>/domain_config.json
/// 不引入 shared_preferences 依赖，保持轻量
class JmDomainPersistence
{
    static const _fileName = 'domain_config.json';

    /// 加载保存的配置
    /// 任何错误都返回空 config（让用户能正常进入应用）
    static Future<JmDomainConfig> load() async
    {
        try
        {
            final f = await _getFile();
            if (!await f.exists()) return const JmDomainConfig();
            final raw = await f.readAsString();
            if (raw.trim().isEmpty) return const JmDomainConfig();
            final json = jsonDecode(raw) as Map<String, dynamic>;
            return JmDomainConfig(
                imageDomains: (json['imageDomains'] as List?)
                    ?.whereType<String>()
                    .toList(),
                apiDomains: (json['apiDomains'] as List?)
                    ?.whereType<String>()
                    .toList(),
                updatedAt: json['updatedAt'] != null
                    ? DateTime.tryParse(json['updatedAt'] as String)
                    : null,
            );
        }
        catch (e)
        {
            return const JmDomainConfig();
        }
    }

    /// 保存配置
    /// 传 null 表示清除该字段
    static Future<void> save({
        List<String>? imageDomains,
        List<String>? apiDomains,
    }) async
    {
        try
        {
            final f = await _getFile();
            // 读取旧配置，保留另一字段
            final old = await load();
            final newImage = imageDomains ?? old.imageDomains;
            final newApi = apiDomains ?? old.apiDomains;
            final json = {
                'imageDomains': newImage,
                'apiDomains': newApi,
                'updatedAt': DateTime.now().toIso8601String(),
            };
            await f.writeAsString(jsonEncode(json));
        }
        catch (e)
        {
            // 静默失败，持久化失败不影响功能
        }
    }

    /// 清除全部持久化（恢复默认值时使用）
    static Future<void> clear() async
    {
        try
        {
            final f = await _getFile();
            if (await f.exists()) await f.delete();
        }
        catch (_) {}
    }

    static Future<File> _getFile() async
    {
        final dir = await getApplicationDocumentsDirectory();
        return File('${dir.path}${Platform.pathSeparator}$_fileName');
    }
}
