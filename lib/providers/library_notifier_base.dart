import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/library_dao.dart';
import '../utils/library_storage.dart';
import 'config_provider.dart';
import 'library_state.dart';

/// 书架 Notifier 基类
/// 抽取公共依赖与工具方法，供各功能 mixin 复用
abstract class LibraryNotifierBase extends StateNotifier<LibraryState>
{
    final LibraryDao _libraryDao;
    final Ref _ref;

    /// 构造基类
    LibraryNotifierBase(this._libraryDao, this._ref) : super(const LibraryState());

    /// 内部 DAO 访问点，供 mixin 使用
    LibraryDao get libraryDao => _libraryDao;

    /// 内部 Ref 访问点，供 mixin 使用
    Ref get ref => _ref;

    /// 解析下载目录
    /// 1) 等待 ConfigNotifier 完成初始化（避免首帧拿到空 downloadDir）
    /// 2) 优先使用 ConfigNotifier 里的 downloadDir（用户实际配置）
    /// 3) 为空时回退到默认下载目录
    Future<String> resolveDownloadDir() async
    {
        await _ref.read(configProvider.notifier).initialized;
        final configured = _ref.read(configProvider).config.downloadDir;
        return LibraryStorage.getDownloadDir(configured: configured);
    }

    /// 在 albumDir 下递归查找第一张可用图片
    /// 用于在没有 cover.jpg 的旧本子上兜底显示首张图
    Future<String?> findFirstImage(String albumDir) async
    {
        try
        {
            final dir = Directory(albumDir);
            if (!await dir.exists()) return null;
            final entries = await dir.list(recursive: true).toList();
            final images = entries
                .whereType<File>()
                .where((f) =>
                    f.path.toLowerCase().endsWith('.jpg') ||
                    f.path.toLowerCase().endsWith('.jpeg') ||
                    f.path.toLowerCase().endsWith('.webp') ||
                    f.path.toLowerCase().endsWith('.png'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
            return images.isEmpty ? null : images.first.path;
        }
        catch (_)
        {
            return null;
        }
    }

    /// 加载书架（由 [LibraryReadMixin] 实现）
    Future<void> loadLibrary();
}
