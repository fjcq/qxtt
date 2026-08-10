import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../common/app_logger.dart';
import '../download/concurrent_image_downloader.dart';
import '../jm/jm_client.dart';
import '../jm/jm_image.dart';
import '../../utils/file_helper.dart';
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

    /// 下载单张图片并持久化到本地
    ///
    /// 【统一阅读】
    /// 与 [enqueue] 不同，本方法不走优先级队列调度，而是直接调用
    /// [downloadOneImageWithDecode] 完成"下载 + 解密 + 写盘 + 写 .ok"全流程，
    /// 返回本地文件绝对路径供阅读器 [Image.file] 直接渲染。
    ///
    /// - [photoId] 章节 ID
    /// - [filename] 图片文件名（如 "00001.jpg"）
    /// - [saveDir] 章节本地目录
    /// - [scrambleId] 解密参数
    /// - [aid] 作品 ID（整数）
    /// - [priority] 下载优先级（仅用于事件标记，不影响调度顺序）
    ///
    /// 返回：本地文件绝对路径
    ///
    /// 异常：
    /// - 离线状态下抛 [StateError]
    /// - 下载失败抛出原始异常
    Future<String> downloadAndSave({
        required String photoId,
        required String filename,
        required String saveDir,
        required int scrambleId,
        required int aid,
        DownloadPriority priority = DownloadPriority.immediate,
        CancelToken? cancelToken,
    }) async
    {
        if (_disposed)
        {
            throw StateError('ReaderDownloadEngine 已释放');
        }
        // 离线状态拒绝下载（已存在的本地文件仍可被读取）
        if (_networkMonitor.isOffline)
        {
            throw StateError('当前处于离线状态');
        }

        // 确保章节目录存在
        await Directory(saveDir).create(recursive: true);

        // 解析页码与本地路径（与 downloadOneImageWithDecode 保持一致）
        // 注意：filename 形如 "00001.jpg"，但本地保存的页码索引需通过文件名前缀推导
        final pageIndex = _parsePageIndexFromFilename(filename);
        final savePath = '$saveDir${Platform.pathSeparator}'
            '${(pageIndex + 1).toString().padLeft(5, '0')}.jpg';
        final okPath = '$savePath.ok';

        // 命中缓存：本地已有 .jpg + .ok 则直接返回
        final saveExists = await FileExistenceCache.fileExists(savePath);
        final okExists = saveExists &&
            await FileExistenceCache.fileExists(okPath);
        if (saveExists && okExists)
        {
            return savePath;
        }

        // 发射进度事件
        _emitRaw(
            '${photoId}_$filename',
            '下载中',
            0.1,
        );

        try
        {
            final token = cancelToken ?? CancelToken();
            final result = await downloadOneImageWithDecode(
                client: _client,
                cancelToken: token,
                photoId: photoId,
                filename: filename,
                pageIndex: pageIndex,
                saveDir: saveDir,
                scrambleId: scrambleId,
                aid: aid,
            );

            if (!result.success)
            {
                throw Exception('下载失败: $filename');
            }

            // 失效缓存让后续读取感知新文件
            FileExistenceCache.invalidate(savePath);
            FileExistenceCache.invalidate(okPath);

            _emitRaw(
                '${photoId}_$filename',
                '完成',
                1.0,
                isDone: true,
            );

            return savePath;
        }
        catch (e, st)
        {
            appLogger.w('[reader_download] downloadAndSave 失败: '
                '$photoId/$filename, $e');
            _emitRaw(
                '${photoId}_$filename',
                '失败',
                0.0,
                error: e.toString(),
            );
            // 取消异常按原始路径返回
            if (e is DioException && CancelToken.isCancel(e))
            {
                rethrow;
            }
            throw Exception('下载并保存失败: $e, $st');
        }
    }

    /// 从文件名推导页码索引（0-based）
    ///
    /// JM 图片文件名形如 "00001.jpg"，去掉扩展名后转 int 减 1 即可。
    /// 解析失败时返回 0（容错处理，避免越界）。
    int _parsePageIndexFromFilename(String filename)
    {
        final dot = filename.lastIndexOf('.');
        final seq = dot > 0 ? filename.substring(0, dot) : filename;
        final parsed = int.tryParse(seq);
        if (parsed == null || parsed < 1) return 0;
        return parsed - 1;
    }

    /// 内部发射进度事件（不走队列，仅广播）
    void _emitRaw(
        String taskKey,
        String stage,
        double progress, {
        bool isDone = false,
        String? error,
    })
    {
        if (_progressController.isClosed) return;
        _progressController.add(ReaderDownloadProgress(
            taskKey: taskKey,
            stage: stage,
            progress: progress,
            isDone: isDone,
            error: error,
        ));
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
