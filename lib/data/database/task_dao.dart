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
            final jsonList = _tasks.map((t) => _toJson(t)).toList();
            await file.writeAsString(jsonEncode(jsonList));
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
            'status': task.status,
            'message': task.message,
            'createdAt': task.createdAt,
            'updatedAt': task.updatedAt,
            'progress': task.progress,
            'currentImage': task.currentImage,
            'totalImages': task.totalImages,
            'title': task.title,
            'coverPath': task.coverPath,
        };
    }

    /// JSON转模型
    DownloadTaskModel _fromJson(Map<String, dynamic> json)
    {
        return DownloadTaskModel()
            ..taskId = json['taskId']?.toString() ?? ''
            ..taskType = json['taskType']?.toString() ?? 'album'
            ..jmId = json['jmId']?.toString() ?? ''
            ..status = json['status']?.toString() ?? 'pending'
            ..message = json['message']?.toString() ?? ''
            ..createdAt = json['createdAt']?.toString() ?? ''
            ..updatedAt = json['updatedAt']?.toString() ?? ''
            ..progress = (json['progress'] as num?)?.toDouble() ?? 0.0
            ..currentImage = (json['currentImage'] as num?)?.toInt() ?? 0
            ..totalImages = (json['totalImages'] as num?)?.toInt() ?? 0
            ..title = json['title']?.toString()
            ..coverPath = json['coverPath']?.toString();
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
