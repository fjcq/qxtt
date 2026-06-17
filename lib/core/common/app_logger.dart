import 'dart:io';

import 'package:path/path.dart' as p;

/// 简化版文件日志器
///
/// 为什么不依赖 logger 库的 MultiOutput + ConsoleOutput + 自定义 Output：
/// - logger 库的 output 是 async fire-and-forget，release Windows 下异常被吞
/// - 主线程的 STARTUP_DIAG.txt 同步写成功但 _FileLogOutput 写的文件全不存在
///   → 证明 logger 库的 output 在 release 下根本没被调或写失败被吞
/// - 这里改成纯 dart:io 同步 FileSink，简单可靠
class AppLogger
{
    static final AppLogger _instance = AppLogger._();
    factory AppLogger() => _instance;
    AppLogger._()
    {
        try
        {
            final exePath = Platform.resolvedExecutable;
            final dir = Directory(p.join(p.dirname(exePath), 'logs'));
            if (!dir.existsSync())
            {
                dir.createSync(recursive: true);
            }
            _dir = dir;
            _openFile();
            // 启动标记：看到 STARTED.txt 就能确认日志系统在工作
            final marker = File(p.join(_dir!.path, 'STARTED.txt'));
            marker.writeAsStringSync(
                'JMComic logger started at ${DateTime.now()}\n'
                'Log file: ${_file!.path}\n',
            );
        }
        catch (e, st)
        {
            // 写一个 ERRORS.txt 让用户能看到具体错误
            try
            {
                final errFile = File(p.join(
                    Directory.current.path, 'logs', 'ERRORS.txt'));
                errFile.parent.createSync(recursive: true);
                errFile.writeAsStringSync(
                    '[${DateTime.now()}] logger init failed: $e\n$st\n',
                    mode: FileMode.append,
                );
            }
            catch (_) {}
        }
    }

    Directory? _dir;
    File? _file;
    IOSink? _sink;
    String? _currentDate;

    void _openFile()
    {
        _closeFile();
        final today = _today();
        _currentDate = today;
        _file = File(p.join(_dir!.path, 'jmcomic-$today.log'));
        _sink = _file!.openWrite(mode: FileMode.append);
    }

    void _closeFile()
    {
        try
        {
            _sink?.flush();
            _sink?.close();
        }
        catch (_) {}
        _sink = null;
    }

    String _today()
    {
        final now = DateTime.now();
        return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    }

    String _now() => DateTime.now().toString();

    void _write(String level, String msg)
    {
        try
        {
            final today = _today();
            if (today != _currentDate)
            {
                _openFile();
            }
            _sink?.writeln('[$_now] [$level] $msg');
            // 立即 flush，避免程序退出时丢日志
            _sink?.flush();
        }
        catch (_) {}
    }

    void i(String msg) => _write('INFO', msg);
    void w(String msg) => _write('WARN', msg);
    void e(String msg) => _write('ERROR', msg);
    void d(String msg) => _write('DEBUG', msg);

    void close() => _closeFile();
}

/// 全局日志器实例
final appLogger = AppLogger();
