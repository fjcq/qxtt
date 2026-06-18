import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/download_task_model.dart';

/// 下载任务数据访问对象（JSON文件持久化）
class TaskDao
{
    List<DownloadTaskModel> _tasks = [];
    bool _loaded = false;

    /// 获取存储文件路径
    Future<String> _getFilePath() async
    {
        final dir = await getApplicationSupportDirectory();
        return '${dir.path}${Platform.pathSeparator}download_tasks.json';
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
                _tasks = jsonList.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
            }
        }
        catch (_)
        {
            _tasks = [];
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
            final jsonList = _tasks.map((t) => _toJson(t)).toList();
            await file.writeAsString(jsonEncode(jsonList), flush: true);
        }
        catch (_)
        {
            // 忽略写入失败
        }
    }

    /// 模型转JSON
    Map<String, dynamic> _toJson(DownloadTaskModel task)
    {
        return {
            'taskId': task.taskId,
            'taskType': task.taskType,
            'jmId': task.jmId,
            'albumId': task.albumId,
            'albumTitle': task.albumTitle,
            'episodeIndex': task.episodeIndex,
            'episodeName': task.episodeName,
            'status': task.status,
            'message': task.message,
            'createdAt': task.createdAt,
            'updatedAt': task.updatedAt,
            'progress': task.progress,
            'currentImage': task.currentImage,
            'totalImages': task.totalImages,
            'title': task.title,
            'coverPath': task.coverPath,
            'firstPhotoId': task.firstPhotoId,
            // 持久化已下载章节列表，应用重启后可恢复 library
            'downloadedPhotoIds': task.downloadedPhotoIds,
            // 持久化 album 元信息，用于应用重启后补全 library 显示
            'coverAuthor': task.coverAuthor,
            'coverPageCount': task.coverPageCount,
            'coverEpisodeCount': task.coverEpisodeCount,
            'localPath': task.localPath,
        };
    }

    /// JSON转模型
    DownloadTaskModel _fromJson(Map<String, dynamic> json)
    {
        // albumId 在旧数据中可能缺失：album 任务时回退到 jmId
        final jmId = json['jmId']?.toString() ?? '';
        final taskType = json['taskType']?.toString() ?? 'album';
        final albumId = json['albumId']?.toString() ?? jmId;
        return DownloadTaskModel()
            ..taskId = json['taskId']?.toString() ?? ''
            ..taskType = taskType
            ..jmId = jmId
            ..albumId = albumId
            ..albumTitle = json['albumTitle']?.toString() ?? ''
            ..episodeIndex = json['episodeIndex']?.toString() ?? ''
            ..episodeName = json['episodeName']?.toString() ?? ''
            ..status = json['status']?.toString() ?? 'pending'
            ..message = json['message']?.toString() ?? ''
            ..createdAt = json['createdAt']?.toString() ?? ''
            ..updatedAt = json['updatedAt']?.toString() ?? ''
            ..progress = (json['progress'] as num?)?.toDouble() ?? 0.0
            ..currentImage = (json['currentImage'] as num?)?.toInt() ?? 0
            ..totalImages = (json['totalImages'] as num?)?.toInt() ?? 0
            ..title = json['title']?.toString()
            ..coverPath = json['coverPath']?.toString()
            ..firstPhotoId = json['firstPhotoId']?.toString()
            // 恢复已下载章节列表（兼容旧数据缺失的情况）
            ..downloadedPhotoIds = (json['downloadedPhotoIds'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[]
            // 恢复 album 元信息（兼容旧数据缺失的情况）
            ..coverAuthor = json['coverAuthor']?.toString() ?? ''
            ..coverPageCount = (json['coverPageCount'] as num?)?.toInt() ?? 0
            ..coverEpisodeCount =
                (json['coverEpisodeCount'] as num?)?.toInt() ?? 0
            ..localPath = json['localPath']?.toString() ?? '';
    }

    /// 更新 firstPhotoId（album 任务下载完成后调用）
    Future<void> updateFirstPhotoId(String taskId, String firstPhotoId) async
    {
        await _ensureLoaded();
        final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task != null)
        {
            task.firstPhotoId = firstPhotoId;
            task.updatedAt = DateTime.now().toIso8601String();
            await _save();
        }
    }

    /// 创建下载任务
    Future<void> createTask(DownloadTaskModel task) async
    {
        await _ensureLoaded();
        _tasks.insert(0, task);
        await _save();
    }

    /// 更新任务状态
    Future<void> updateTaskStatus(
        String taskId,
        String status,
        String message,
        double progress,
    ) async
    {
        await _ensureLoaded();
        final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task != null)
        {
            task.status = status;
            task.message = message;
            task.progress = progress;
            task.updatedAt = DateTime.now().toIso8601String();
            await _save();
        }
    }

    /// 更新任务进度
    Future<void> updateTaskProgress(
        String taskId,
        int currentImage,
        int totalImages,
        double progress,
    ) async
    {
        await _ensureLoaded();
        final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
        if (task != null)
        {
            task.currentImage = currentImage;
            task.totalImages = totalImages;
            task.progress = progress;
            task.updatedAt = DateTime.now().toIso8601String();
            await _save();
        }
    }

    /// 获取所有任务
    Future<List<DownloadTaskModel>> getAllTasks() async
    {
        await _ensureLoaded();
        return List.from(_tasks);
    }

    /// 删除任务
    Future<void> deleteTask(String taskId) async
    {
        await _ensureLoaded();
        _tasks.removeWhere((t) => t.taskId == taskId);
        await _save();
    }

    /// 清除已完成任务
    Future<int> clearCompletedTasks() async
    {
        await _ensureLoaded();
        final count = _tasks.where((t) => t.status == 'completed').length;
        _tasks.removeWhere((t) => t.status == 'completed');
        await _save();
        return count;
    }
}
