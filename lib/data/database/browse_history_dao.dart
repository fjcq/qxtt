import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 浏览历史模型
class BrowseHistoryModel
{
    /// 本子 ID
    late String albumId;

    /// 标题
    late String title;

    /// 封面 URL
    late String coverUrl;

    /// 作者
    late String author;

    /// 浏览时间
    late String browsedAt;

    /// 最后阅读页码
    late int lastReadPage;
}

/// 浏览历史数据访问对象（JSON文件持久化）
class BrowseHistoryDao
{
    List<BrowseHistoryModel> _history = [];
    bool _loaded = false;

    /// 获取存储文件路径
    Future<String> _getFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}browse_history.json';
    }

    /// 确保数据已从文件加载
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
                final jsonList = jsonDecode(content) as List<dynamic>;
                _history = jsonList
                    .map((e) => _fromJson(e as Map<String, dynamic>))
                    .toList();
            }
        }
        catch (_)
        {
            _history = [];
        }
    }

    /// 保存数据到文件
    Future<void> _save() async
    {
        try
        {
            final file = File(await _getFilePath());
            final jsonList = _history.map((h) => _toJson(h)).toList();
            await file.writeAsString(jsonEncode(jsonList));
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 模型转JSON
    Map<String, dynamic> _toJson(BrowseHistoryModel h)
    {
        return {
            'albumId': h.albumId,
            'title': h.title,
            'coverUrl': h.coverUrl,
            'author': h.author,
            'browsedAt': h.browsedAt,
            'lastReadPage': h.lastReadPage,
        };
    }

    /// JSON转模型
    BrowseHistoryModel _fromJson(Map<String, dynamic> json)
    {
        return BrowseHistoryModel()
            ..albumId = json['albumId']?.toString() ?? ''
            ..title = json['title']?.toString() ?? ''
            ..coverUrl = json['coverUrl']?.toString() ?? ''
            ..author = json['author']?.toString() ?? ''
            ..browsedAt = json['browsedAt']?.toString() ?? ''
            ..lastReadPage = (json['lastReadPage'] as num?)?.toInt() ?? 0;
    }

    /// 添加浏览记录（已存在则更新）
    Future<void> addHistory(BrowseHistoryModel item) async
    {
        await _ensureLoaded();
        _history.removeWhere((h) => h.albumId == item.albumId);
        _history.insert(0, item);
        // 最多保留200条
        if (_history.length > 200)
        {
            _history = _history.sublist(0, 200);
        }
        await _save();
    }

    /// 获取所有浏览历史
    Future<List<BrowseHistoryModel>> getAllHistory() async
    {
        await _ensureLoaded();
        return List.from(_history);
    }

    /// 删除单条历史
    Future<void> deleteHistory(String albumId) async
    {
        await _ensureLoaded();
        _history.removeWhere((h) => h.albumId == albumId);
        await _save();
    }

    /// 清空所有历史
    Future<void> clearAllHistory() async
    {
        await _ensureLoaded();
        _history.clear();
        await _save();
    }
}
