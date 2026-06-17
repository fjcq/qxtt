import 'dart:io';

/// 打开本地目录工具
/// 在 Windows / macOS / Linux 上分别调用系统文件管理器
class DirectoryOpener
{
    // 私有构造函数
    DirectoryOpener._();

    /// 打开本地目录
    /// [dirPath] 目标目录绝对路径
    /// 返回 true 表示成功派发到系统
    /// 注意：返回值不代表系统是否真正打开，仅表示命令是否成功启动
    static Future<bool> open(String dirPath) async
    {
        if (dirPath.isEmpty) return false;
        // 目录不存在时直接返回 false，由调用方给出提示
        final dir = Directory(dirPath);
        if (!await dir.exists()) return false;

        try
        {
            if (Platform.isWindows)
            {
                // Windows: 用 explorer 打开
                // ignore: deprecated_member_use
                await Process.start('explorer', [dirPath], mode: ProcessStartMode.detached);
                return true;
            }
            else if (Platform.isMacOS)
            {
                // macOS: open <path>
                await Process.start('open', [dirPath], mode: ProcessStartMode.detached);
                return true;
            }
            else if (Platform.isLinux)
            {
                // Linux: xdg-open
                await Process.start('xdg-open', [dirPath], mode: ProcessStartMode.detached);
                return true;
            }
            return false;
        }
        catch (_)
        {
            return false;
        }
    }
}
