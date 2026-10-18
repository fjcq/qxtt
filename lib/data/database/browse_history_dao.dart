import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/common/app_logger.dart';

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

    /// 最后阅读的章节 ID（在线阅读器进度记忆用）
    String? lastReadPhotoId;
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
        catch (e)
        {
            // 加载失败不阻断业务，但记录日志便于排查数据丢失问题
            _history = [];
            appLogger.w('BrowseHistoryDao 加载浏览历史失败: $e');
        }
    }

    /// 保存数据到文件
    Future<void> _save() async
    {
        try
        {
            final file = File(await _getFilePath());
            // 显式创建父目录，避免在 Windows 首次运行时因
            // getApplicationSupportDirectory 返回的子目录尚未创建而写入失败
            await file.parent.create(recursive: true);
            final jsonList = _history.map((h) => _toJson(h)).toList();
            await file.writeAsString(jsonEncode(jsonList), flush: true);
        }
        catch (e)
        {
            // 忽略写入失败，但记录日志
            appLogger.w('BrowseHistoryDao 保存浏览历史失败: $e');
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
            'lastReadPhotoId': h.lastReadPhotoId,
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
            ..lastReadPage = (json['lastReadPage'] as num?)?.toInt() ?? 0
            ..lastReadPhotoId = json['lastReadPhotoId']?.toString();
    }

    /// 添加浏览记录（已存在则仅更新元数据并置顶，保留已有阅读进度）
    Future<void> addHistory(BrowseHistoryModel item) async
    {
        await _ensureLoaded();
        final idx = _history.indexWhere((h) => h.albumId == item.albumId);
        if (idx >= 0)
        {
            // 已存在：保留阅读进度，避免详情页重复记录时把进度重置为 0
            final existing = _history.removeAt(idx);
            item.lastReadPage = existing.lastReadPage;
            item.lastReadPhotoId = existing.lastReadPhotoId;
        }
        _history.insert(0, item);
        // 最多保留200条
        if (_history.length > 200)
        {
            _history = _history.sublist(0, 200);
        }
        await _save();
    }

    /// 更新阅读进度（如果记录不存在则不操作）
    /// [page] 0-based 页码
    /// [photoId] 章节 ID
    Future<void> updateReadProgress(String albumId, int page, String photoId) async
    {
        await _ensureLoaded();
        final idx = _history.indexWhere((h) => h.albumId == albumId);
        if (idx < 0) return;
        final h = _history[idx];
        h.lastReadPage = page;
        h.lastReadPhotoId = photoId;
        h.browsedAt = DateTime.now().toIso8601String();
        // 移到最前
        _history.removeAt(idx);
        _history.insert(0, h);
        await _save();
    }

    /// 读取指定 album 的历史（不存在返回 null）
    Future<BrowseHistoryModel?> getHistory(String albumId) async
    {
        await _ensureLoaded();
        for (final h in _history)
        {
            if (h.albumId == albumId) return h;
        }
        return null;
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
