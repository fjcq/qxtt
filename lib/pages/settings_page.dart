import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/config_provider.dart';
import '../data/models/app_config_model.dart';
import '../core/jm/jm_image.dart';
import '../theme/app_colors.dart';

/// 设置页
class SettingsPage extends ConsumerWidget
{
    const SettingsPage({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final configState = ref.watch(configProvider);
        final config = configState.config;

        return Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: ListView(
                children: [
                    // ===== 下载设置 =====
                    _buildSectionHeader('下载设置'),
                    ListTile(
                        leading: const Icon(Icons.folder_outlined, color: AppColors.accent),
                        title: const Text('下载目录'),
                        subtitle: Text(
                            config.downloadDir.isEmpty ? '默认目录' : config.downloadDir,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _showDownloadDirPicker(context, ref),
                    ),
                    ListTile(
                        leading: const Icon(Icons.image_outlined, color: AppColors.accent),
                        title: const Text('图片解密'),
                        subtitle: const Text('下载时自动解密图片', style: TextStyle(fontSize: 12)),
                        trailing: Switch(
                            value: config.decodeImage,
                            activeThumbColor: AppColors.accent,
                            onChanged: (value) => ref.read(configProvider.notifier).updateConfig(
                                config.copyWith(decodeImage: value),
                            ),
                        ),
                    ),
                    ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.accent),
                        title: const Text('清理解密缓存'),
                        subtitle: const Text('清理在线观看时缓存的解密图片；算法更新后建议执行', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _clearDecodedCache(context),
                    ),
                    ListTile(
                        leading: const Icon(Icons.settings_outlined, color: AppColors.accent),
                        title: const Text('图片线程数'),
                        subtitle: Text('${config.imageThreadCount}'),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _showThreadCountPicker(
                            context, ref, 'imageThreadCount', config.imageThreadCount,
                        ),
                    ),
                    ListTile(
                        leading: const Icon(Icons.cached, color: AppColors.accent),
                        title: const Text('预加载页数'),
                        subtitle: Text('${config.preloadPageCount}'),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _showPreloadPageCountPicker(context, ref, config),
                    ),

                    // ===== 网络设置 =====
                    _buildSectionHeader('网络设置'),
                    ListTile(
                        leading: const Icon(Icons.dns_outlined, color: AppColors.accent),
                        title: const Text('域名管理'),
                        subtitle: const Text('切换/测试/获取最新图片与 API 域名', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => context.push('/settings/domains'),
                    ),
                    ListTile(
                        leading: const Icon(Icons.vpn_lock_outlined, color: AppColors.accent),
                        title: const Text('使用代理'),
                        trailing: Switch(
                            value: config.useProxy,
                            activeThumbColor: AppColors.accent,
                            onChanged: (value) => ref.read(configProvider.notifier).updateProxy(
                                url: config.proxyUrl,
                                enabled: value,
                            ),
                        ),
                    ),
                    if (config.useProxy)
                        ListTile(
                            leading: const Icon(Icons.link, color: AppColors.accent),
                            title: const Text('代理地址'),
                            subtitle: Text(
                                config.proxyUrl.isEmpty ? '未设置' : config.proxyUrl,
                                style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                            onTap: () => _showProxyEditor(context, ref, config),
                        ),

                    // ===== 显示设置 =====
                    _buildSectionHeader('显示设置'),
                    ListTile(
                        leading: const Icon(Icons.dark_mode_outlined, color: AppColors.accent),
                        title: const Text('主题模式'),
                        subtitle: Text(_getThemeModeLabel(config.themeMode)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _showThemeModePicker(context, ref, config),
                    ),
                    ListTile(
                        leading: const Icon(Icons.auto_stories, color: AppColors.accent),
                        title: const Text('默认阅读模式'),
                        subtitle: Text(_getReaderModeLabel(config.readerMode)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => _showReaderModePicker(context, ref, config),
                    ),

                    // ===== 关于 =====
                    _buildSectionHeader('关于'),
                    const ListTile(
                        leading: Icon(Icons.info_outline, color: AppColors.accent),
                        title: Text('版本'),
                        subtitle: Text('1.0.0'),
                    ),
                    ListTile(
                        leading: const Icon(Icons.code, color: AppColors.accent),
                        title: const Text('下载管理'),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
                        onTap: () => context.push('/downloads'),
                    ),
                ],
            ),
        );
    }

    /// 构建分组标题
    Widget _buildSectionHeader(String title)
    {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
                title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                ),
            ),
        );
    }

    /// 获取主题模式标签
    String _getThemeModeLabel(String mode)
    {
        switch (mode)
        {
            case 'dark':
                return '深色';
            case 'light':
                return '浅色';
            case 'system':
                return '跟随系统';
            default:
                return mode;
        }
    }

    /// 获取阅读模式标签
    String _getReaderModeLabel(String mode)
    {
        switch (mode)
        {
            case 'vertical':
                return '纵向滚动';
            case 'horizontal':
                return '横向翻页';
            case 'webtoon':
                return 'Webtoon';
            default:
                return mode;
        }
    }

    /// 显示下载目录选择器
    void _showDownloadDirPicker(BuildContext context, WidgetRef ref)
    {
        // 简化实现，实际应使用文件选择器
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请使用系统文件选择器')),
        );
    }

    /// 显示线程数选择器
    void _showThreadCountPicker(
        BuildContext context,
        WidgetRef ref,
        String field,
        int current,
    )
    {
        showDialog(
            context: context,
            builder: (context) => SimpleDialog(
                title: const Text('选择线程数'),
                children: [1, 3, 5, 8, 10].map((count) =>
                    SimpleDialogOption(
                        onPressed: ()
                        {
                            final config = ref.read(configProvider).config;
                            if (field == 'imageThreadCount')
                            {
                                ref.read(configProvider.notifier).updateConfig(
                                    config.copyWith(imageThreadCount: count),
                                );
                            }
                            else
                            {
                                ref.read(configProvider.notifier).updateConfig(
                                    config.copyWith(photoThreadCount: count),
                                );
                            }
                            Navigator.pop(context);
                        },
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text('$count'),
                                if (count == current)
                                    const Icon(Icons.check, color: AppColors.accent, size: 20),
                            ],
                        ),
                    ),
                ).toList(),
            ),
        );
    }

    /// 显示代理编辑器
    void _showProxyEditor(BuildContext context, WidgetRef ref, AppConfigModel config)
    {
        final controller = TextEditingController(text: config.proxyUrl);
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('代理地址'),
                content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                        hintText: '例如: 127.0.0.1:7890',
                    ),
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                    ),
                    ElevatedButton(
                        onPressed: ()
                        {
                            ref.read(configProvider.notifier).updateProxy(
                                url: controller.text,
                                enabled: config.useProxy,
                            );
                            Navigator.pop(context);
                        },
                        child: const Text('确定'),
                    ),
                ],
            ),
        );
    }

    /// 显示主题模式选择器
    void _showThemeModePicker(BuildContext context, WidgetRef ref, AppConfigModel config)
    {
        showDialog(
            context: context,
            builder: (context) => SimpleDialog(
                title: const Text('主题模式'),
                children: ['dark', 'light', 'system'].map((mode) =>
                    SimpleDialogOption(
                        onPressed: ()
                        {
                            ref.read(configProvider.notifier).updateThemeMode(mode);
                            Navigator.pop(context);
                        },
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(_getThemeModeLabel(mode)),
                                if (mode == config.themeMode)
                                    const Icon(Icons.check, color: AppColors.accent, size: 20),
                            ],
                        ),
                    ),
                ).toList(),
            ),
        );
    }

    /// 显示阅读模式选择器
    void _showReaderModePicker(BuildContext context, WidgetRef ref, AppConfigModel config)
    {
        showDialog(
            context: context,
            builder: (context) => SimpleDialog(
                title: const Text('默认阅读模式'),
                children: ['vertical', 'horizontal', 'webtoon'].map((mode) =>
                    SimpleDialogOption(
                        onPressed: ()
                        {
                            ref.read(configProvider.notifier).updateReaderMode(mode);
                            Navigator.pop(context);
                        },
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(_getReaderModeLabel(mode)),
                                if (mode == config.readerMode)
                                    const Icon(Icons.check, color: AppColors.accent, size: 20),
                            ],
                        ),
                    ),
                ).toList(),
            ),
        );
    }

    /// 显示预加载页数选择器
    void _showPreloadPageCountPicker(
        BuildContext context,
        WidgetRef ref,
        AppConfigModel config,
    )
    {
        showDialog(
            context: context,
            builder: (context) => SimpleDialog(
                title: const Text('预加载页数'),
                children: [0, 1, 2, 3, 4, 5].map((count) =>
                    SimpleDialogOption(
                        onPressed: ()
                        {
                            ref.read(configProvider.notifier)
                                .updatePreloadPageCount(count);
                            Navigator.pop(context);
                        },
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(count == 0 ? '关闭' : '前后各 $count 页'),
                                if (count == config.preloadPageCount)
                                    const Icon(Icons.check, color: AppColors.accent, size: 20),
                            ],
                        ),
                    ),
                ).toList(),
            ),
        );
    }

    /// 清理解密缓存（在线观看缓存）
    /// 修改解密算法或参数后，旧缓存会用错 aid 解密过的图，导致仍然错位
    Future<void> _clearDecodedCache(BuildContext context) async
    {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text('清理解密缓存'),
                content: const Text('将清理在线观看时缓存的所有解密图片。\n'
                    '下次观看时会重新下载并解密。\n'
                    '已下载到本地的图片不受影响。'),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                    ),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清理'),
                    ),
                ],
            ),
        );
        if (confirmed != true) return;
        if (!context.mounted) return;

        await JmImageCacheManager.clearDecoded();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('解密缓存已清理')),
        );
    }
}
