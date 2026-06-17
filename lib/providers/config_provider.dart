import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database/config_dao.dart';
import '../data/models/app_config_model.dart';

/// 配置状态
class ConfigState
{
    /// 应用配置
    final AppConfigModel config;

    /// 是否正在加载
    final bool isLoading;

    ConfigState({
        AppConfigModel? config,
        this.isLoading = false,
    }) : config = config ?? AppConfigModel();

    ConfigState copyWith({
        AppConfigModel? config,
        bool? isLoading,
    })
    {
        return ConfigState(
            config: config ?? this.config,
            isLoading: isLoading ?? this.isLoading,
        );
    }
}

/// 配置 Provider
/// 关键设计：
/// - 构造时立即触发 _loadAndInit() 异步加载磁盘上的配置 + 填充默认下载目录
/// - 提供 initialized Future 供其他 Provider 等待配置就绪，
///   避免在删除/打开目录等场景下拿到空的 downloadDir
/// - 所有更新配置的方法都会同步把配置持久化到磁盘，确保重启后仍然生效
class ConfigNotifier extends StateNotifier<ConfigState>
{
    /// 初始化完成的 Future
    /// 任何依赖 downloadDir 等配置的 Provider 都应 await 这个 Future 后再 read config
    late final Future<void> initialized = _loadAndInit();

    /// 防重复：多次调用 _save 时合并写入
    Timer? _saveDebounce;

    ConfigNotifier() : super(ConfigState())
    {
        // 触发初始化（不 await，外部可通过 initialized 等待）
        // ignore: discarded_futures
        initialized;
    }

    /// 加载磁盘配置 + 填充默认下载目录
    Future<void> _loadAndInit() async
    {
        state = state.copyWith(isLoading: true);
        try
        {
            // 1) 先尝试从磁盘恢复
            final saved = await ConfigDao().load();
            if (saved != null)
            {
                state = state.copyWith(config: saved);
            }
            // 2) downloadDir 仍为空时，填充默认目录
            if (state.config.downloadDir.isEmpty)
            {
                final dir = await getApplicationDocumentsDirectory();
                final defaultDir =
                    '${dir.path}${Platform.pathSeparator}downloads';
                state = state.copyWith(
                    config: state.config.copyWith(downloadDir: defaultDir),
                );
                // 写回磁盘，避免下次再走默认
                await ConfigDao().save(state.config);
            }
        }
        catch (_)
        {
            // 出错时至少保证 downloadDir 有一个可用值
            if (state.config.downloadDir.isEmpty)
            {
                try
                {
                    final dir = await getApplicationDocumentsDirectory();
                    state = state.copyWith(
                        config: state.config.copyWith(
                            downloadDir:
                                '${dir.path}${Platform.pathSeparator}downloads',
                        ),
                    );
                }
                catch (_)
                {
                    // 极端情况下保留空
                }
            }
        }
        finally
        {
            if (mounted)
            {
                state = state.copyWith(isLoading: false);
            }
        }
    }

    /// 内部：把当前配置写回磁盘（debounce 合并）
    void _persist()
    {
        _saveDebounce?.cancel();
        _saveDebounce = Timer(const Duration(milliseconds: 100), () async
        {
            try
            {
                await ConfigDao().save(state.config);
            }
            catch (_)
            {
                // 持久化失败不影响内存状态
            }
        });
    }

    /// 更新配置
    void updateConfig(AppConfigModel config)
    {
        state = state.copyWith(config: config);
        _persist();
    }

    /// 更新下载目录
    void updateDownloadDir(String dir)
    {
        state = state.copyWith(
            config: state.config.copyWith(downloadDir: dir),
        );
        _persist();
    }

    /// 更新代理设置
    void updateProxy({required String url, required bool enabled})
    {
        state = state.copyWith(
            config: state.config.copyWith(
                proxyUrl: url,
                useProxy: enabled,
            ),
        );
        _persist();
    }

    /// 更新主题模式
    void updateThemeMode(String mode)
    {
        state = state.copyWith(
            config: state.config.copyWith(themeMode: mode),
        );
        _persist();
    }

    /// 更新阅读器模式
    void updateReaderMode(String mode)
    {
        state = state.copyWith(
            config: state.config.copyWith(readerMode: mode),
        );
        _persist();
    }

    @override
    void dispose()
    {
        _saveDebounce?.cancel();
        super.dispose();
    }
}

/// 配置 Provider 实例
final configProvider = StateNotifierProvider<ConfigNotifier, ConfigState>((ref)
{
    return ConfigNotifier();
});
