import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class ConfigNotifier extends StateNotifier<ConfigState>
{
    ConfigNotifier() : super(ConfigState());

    /// 更新配置
    void updateConfig(AppConfigModel config)
    {
        state = state.copyWith(config: config);
    }

    /// 更新下载目录
    void updateDownloadDir(String dir)
    {
        state = state.copyWith(
            config: state.config.copyWith(downloadDir: dir),
        );
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
    }

    /// 更新主题模式
    void updateThemeMode(String mode)
    {
        state = state.copyWith(
            config: state.config.copyWith(themeMode: mode),
        );
    }

    /// 更新阅读器模式
    void updateReaderMode(String mode)
    {
        state = state.copyWith(
            config: state.config.copyWith(readerMode: mode),
        );
    }
}

/// 配置 Provider 实例
final configProvider = StateNotifierProvider<ConfigNotifier, ConfigState>((ref)
{
    return ConfigNotifier();
});
