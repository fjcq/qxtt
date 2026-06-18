import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../jm/jm_client.dart';
import '../jm/jm_image.dart';
import 'network_monitor.dart';

/// 下载任务优先级
enum DownloadPriority
{
    /// 当前显示页，必须立即加载
    immediate,

    /// 前后预加载页
    preload,

    /// 后台章节预取
    background,
}

/// 阅读下载进度事件
class ReaderDownloadProgress
{
    /// 任务唯一标识：photoId_filename
    final String taskKey;

    /// 阶段描述
    final String stage;

    /// 0.0 ~ 1.0
    final double progress;

    /// 是否已完成
    final bool isDone;

    /// 错误信息（失败时）
    final String? error;

    const ReaderDownloadProgress({
        required this.taskKey,
        required this.stage,
        required this.progress,
        this.isDone = false,
        this.error,
    });
}

/// 内部下载任务
class _DownloadTask
{
    final String photoId;
    final String filename;
    final int scrambleId;
    final int aid;
    DownloadPriority priority;
    final DateTime createdAt;
    final CancelToken cancelToken;
    final void Function(ReaderDownloadProgress)? onProgress;
    final Completer<Uint8List> completer;

    _DownloadTask({
        required this.photoId,
        required this.filename,
        required this.scrambleId,
        required this.aid,
        required this.priority,
        required this.cancelToken,
        this.onProgress,
    }) : completer = Completer<Uint8List>(),
         createdAt = DateTime.now();

    /// 任务唯一键
    String get key => '${photoId}_$filename';

    /// 优先级数值，越小越优先
    int get priorityValue
    {
        switch (priority)
        {
            case DownloadPriority.immediate:
                return 0;
            case DownloadPriority.preload:
                return 1;
            case DownloadPriority.background:
                return 2;
        }
    }
}

/// 多线程阅读图片下载引擎
/// 职责：
///   1. 维护带优先级的下载任务队列
///   2. 控制并发数（默认 5，可动态调整）
///   3. 高优先级任务到达时，可抢占低优先级任务释放连接槽
///   4. 解密后的 JPEG 字节返回给调用方
class ReaderDownloadEngine
{
    final JmClient _client;
    final NetworkMonitor _networkMonitor;
    int _concurrency;

    /// 等待队列
    final List<_DownloadTask> _queue = [];

    /// 正在运行的任务
    final Map<String, _DownloadTask> _running = {};

    /// 全局进度流（可选订阅）
    final _progressController = StreamController<ReaderDownloadProgress>.broadcast();

    /// 是否已释放
    bool _disposed = false;

    ReaderDownloadEngine({
        required JmClient client,
        NetworkMonitor? networkMonitor,
        int concurrency = 5,
    })  : _client = client,
          _networkMonitor = networkMonitor ?? NetworkMonitor(),
          _concurrency = concurrency.clamp(1, 10),
          _userConcurrency = concurrency.clamp(1, 10)
    {
        _networkMonitor.init().then((_) => _applyNetworkPolicy());
        _networkMonitor.onConnectivityChanged.listen((_) => _applyNetworkPolicy());
    }

    /// 全局下载进度流
    Stream<ReaderDownloadProgress> get onProgress => _progressController.stream;

    /// 当前并发数
    int get concurrency => _concurrency;

    /// 设置并发数（动态调整）
    set concurrency(int value)
    {
        _concurrency = value.clamp(1, 10);
        _pump();
    }

    /// 将图片加入下载队列
    /// 返回解密后的 JPEG 字节
    /// [priority] 优先级，默认 background
    Future<Uint8List> enqueue({
        required String photoId,
        required String filename,
        required int scrambleId,
        required int aid,
        DownloadPriority priority = DownloadPriority.background,
        CancelToken? cancelToken,
        void Function(ReaderDownloadProgress)? onProgress,
    }) async
    {
        if (_disposed)
        {
            throw StateError('ReaderDownloadEngine 已释放');
        }

        // 离线状态下只允许 immediate 任务（已缓存图片不受影响）
        if (_networkMonitor.isOffline && priority != DownloadPriority.immediate)
        {
            throw StateError('当前处于离线状态');
        }

        final key = '${photoId}_$filename';

        // 如果同一任务已在运行或等待，提升优先级并返回同一个 Future
        final existing = _running[key] ?? _queue.firstWhere(
            (t) => t.key == key,
            orElse: () => _DownloadTask(
                photoId: '',
                filename: '',
                scrambleId: 0,
                aid: 0,
                priority: priority,
                cancelToken: CancelToken(),
            ),
        );

        if (existing.photoId.isNotEmpty)
        {
            // 提升优先级
            if (priority.index < existing.priority.index)
            {
                existing.priority = priority;
                _sortQueue();
                if (_running.containsKey(key))
                {
                    _pump();
                }
            }
            return existing.completer.future;
        }

        final task = _DownloadTask(
            photoId: photoId,
            filename: filename,
            scrambleId: scrambleId,
            aid: aid,
            priority: priority,
            cancelToken: cancelToken ?? CancelToken(),
            onProgress: onProgress,
        );

        _queue.add(task);
        _sortQueue();
        _pump();

        return task.completer.future;
    }

    /// 取消指定任务
    void cancel(String photoId, String filename)
    {
        final key = '${photoId}_$filename';
        final running = _running[key];
        if (running != null)
        {
            if (!running.cancelToken.isCancelled)
            {
                running.cancelToken.cancel('优先级降低或页面离开');
            }
        }

        _queue.removeWhere((t) => t.key == key);
    }

    /// 用户设置的目标并发数（网络恢复后回退到该值）
    final int _userConcurrency;

    /// 根据网络状态调整并发数
    void _applyNetworkPolicy()
    {
        if (_networkMonitor.isOffline)
        {
            _concurrency = 0;
            // 离线时取消所有非 immediate 任务
            for (final task in _running.values.toList())
            {
                if (task.priority != DownloadPriority.immediate &&
                    !task.cancelToken.isCancelled)
                {
                    task.cancelToken.cancel('离线状态，暂停非必要下载');
                }
            }
            _queue.removeWhere((task) => task.priority != DownloadPriority.immediate);
        }
        else
        {
            _concurrency = _networkMonitor.recommendedConcurrency(_userConcurrency);
        }
        _pump();
    }

    /// 释放资源
    void dispose()
    {
        _disposed = true;
        for (final task in _running.values)
        {
            if (!task.cancelToken.isCancelled)
            {
                task.cancelToken.cancel('引擎释放');
            }
        }
        _running.clear();
        _queue.clear();
        _networkMonitor.dispose();
        _progressController.close();
    }

    /// 队列排序：优先级高 → 低，同优先级先创建 → 后创建
    void _sortQueue()
    {
        _queue.sort((a, b)
        {
            final p = a.priorityValue.compareTo(b.priorityValue);
            if (p != 0) return p;
            return a.createdAt.compareTo(b.createdAt);
        });
    }

    /// 调度任务
    void _pump()
    {
        if (_disposed) return;

        // 当前 immediate 任务过多时，可取消部分 background 任务释放槽位
        _evictBackgroundIfNeeded();

        while (_running.length < _concurrency && _queue.isNotEmpty)
        {
            final task = _queue.removeAt(0);
            if (task.completer.isCompleted) continue;
            _running[task.key] = task;
            _execute(task);
        }
    }

    /// 如果 immediate 任务等待且运行槽已满，取消最老的 background 任务
    void _evictBackgroundIfNeeded()
    {
        final hasWaitingImmediate = _queue.any(
            (t) => t.priority == DownloadPriority.immediate,
        );
        if (!hasWaitingImmediate) return;
        if (_running.length < _concurrency) return;

        final background = _running.values
            .where((t) => t.priority == DownloadPriority.background)
            .toList();
        if (background.isEmpty) return;

        background.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final victim = background.first;
        if (!victim.cancelToken.isCancelled)
        {
            victim.cancelToken.cancel('为 immediate 任务释放连接');
        }
    }

    /// 执行单个任务
    Future<void> _execute(_DownloadTask task) async
    {
        _emit(task, '下载中', 0.1);

        try
        {
            final imageBytes = await _client.downloadImage(
                task.photoId,
                task.filename,
                cancelToken: task.cancelToken,
            );

            _emit(task, '解码中', 0.5);
            final decoded = await JmImage.decode(
                Uint8List.fromList(imageBytes),
                task.scrambleId,
                task.aid,
                task.filename,
            );

            _emit(task, '完成', 1.0, isDone: true);
            task.completer.complete(decoded);
        }
        on DioException catch (e)
        {
            if (CancelToken.isCancel(e))
            {
                _emit(task, '已取消', 0.0, error: '已取消');
                if (!task.completer.isCompleted)
                {
                    task.completer.completeError(Exception('已取消'));
                }
            }
            else
            {
                _emit(task, '失败', 0.0, error: e.toString());
                if (!task.completer.isCompleted)
                {
                    task.completer.completeError(e);
                }
            }
        }
        catch (e)
        {
            _emit(task, '失败', 0.0, error: e.toString());
            if (!task.completer.isCompleted)
            {
                task.completer.completeError(e);
            }
        }
        finally
        {
            _running.remove(task.key);
            _pump();
        }
    }

    /// 发射进度事件
    void _emit(
        _DownloadTask task,
        String stage,
        double progress, {
        bool isDone = false,
        String? error,
    })
    {
        final event = ReaderDownloadProgress(
            taskKey: task.key,
            stage: stage,
            progress: progress,
            isDone: isDone,
            error: error,
        );

        if (!_progressController.isClosed)
        {
            _progressController.add(event);
        }

        task.onProgress?.call(event);
    }
}
