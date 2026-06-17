import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_config_model.dart';

/// 应用配置数据访问对象（JSON 文件持久化）
/// 存储位置：${appSupportDir}/app_config.json
class ConfigDao
{
    /// 内存缓存，避免每次 read 都打文件
    AppConfigModel? _cache;
    bool _loaded = false;

    /// 获取存储文件路径
    Future<String> _getFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}app_config.json';
    }

    /// 确保从文件加载一次
    Future<void> _ensureLoaded() async
    {
        if (_loaded) return;
        _loaded = true;
        try
        {
            final file = File(await _getFilePath());
            if (await file.exists())
            {
                final content = await file.readAsString();
                final json = jsonDecode(content) as Map<String, dynamic>;
                _cache = AppConfigModel.fromJson(json);
            }
        }
        catch (_)
        {
            _cache = null;
        }
    }

    /// 加载当前配置
    /// 返回 null 表示文件不存在或解析失败（首次启动场景）
    Future<AppConfigModel?> load() async
    {
        await _ensureLoaded();
        return _cache;
    }

    /// 保存配置到磁盘
    /// 写入失败时不抛异常，避免影响内存状态
    Future<void> save(AppConfigModel config) async
    {
        _cache = config;
        try
        {
            final file = File(await _getFilePath());
            // 显式创建父目录，Windows 首次运行时 appSupportDir 子目录可能未创建
            await file.parent.create(recursive: true);
            await file.writeAsString(
                jsonEncode(config.toJson()),
                flush: true,
            );
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 强制重新从文件加载（用于调试/设置页手动刷新）
    Future<AppConfigModel?> reload() async
    {
        _loaded = false;
        _cache = null;
        await _ensureLoaded();
        return _cache;
    }
}
