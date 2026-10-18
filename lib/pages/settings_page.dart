import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_version.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';
import '../data/models/app_config_model.dart';
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
        final authState = ref.watch(authProvider);

        return Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: ListView(
                children: [
                    // ===== 账号 =====
                    ..._buildAccountSection(context, ref, authState),

                    // ===== 下载设置 =====
                    _buildSectionHeader(context, '下载设置'),
                    ListTile(
                        leading: Icon(Icons.folder_outlined, color: context.appColors.accent),
                        title: const Text('下载目录'),
                        subtitle: Text(
                            config.downloadDir.isEmpty ? '默认目录' : config.downloadDir,
                            style: TextStyle(fontSize: 12, color: context.appColors.textSecondary),
                        ),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => _showDownloadDirPicker(context, ref),
                    ),
                    ListTile(
                        leading: Icon(Icons.settings_outlined, color: context.appColors.accent),
                        title: const Text('图片线程数'),
                        subtitle: Text(
                            '${config.imageThreadCount}（影响手动下载、阅读预下载、阅读即时下载）',
                            style: TextStyle(fontSize: 12, color: context.appColors.textSecondary),
                        ),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => _showThreadCountPicker(
                            context, ref, 'imageThreadCount', config.imageThreadCount,
                        ),
                    ),
                    ListTile(
                        leading: Icon(Icons.cached, color: context.appColors.accent),
                        title: const Text('预加载页数'),
                        subtitle: Text('${config.preloadPageCount}'),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => _showPreloadPageCountPicker(context, ref, config),
                    ),

                    // ===== 网络设置 =====
                    _buildSectionHeader(context, '网络设置'),
                    ListTile(
                        leading: Icon(Icons.dns_outlined, color: context.appColors.accent),
                        title: const Text('域名管理'),
                        subtitle: const Text('切换/测试/获取最新图片与 API 域名', style: TextStyle(fontSize: 12)),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => context.push('/settings/domains'),
                    ),
                    ListTile(
                        leading: Icon(Icons.vpn_lock_outlined, color: context.appColors.accent),
                        title: const Text('使用代理'),
                        trailing: Switch(
                            value: config.useProxy,
                            activeThumbColor: context.appColors.accent,
                            onChanged: (value) => ref.read(configProvider.notifier).updateProxy(
                                url: config.proxyUrl,
                                enabled: value,
                            ),
                        ),
                    ),
                    if (config.useProxy)
                        ListTile(
                            leading: Icon(Icons.link, color: context.appColors.accent),
                            title: const Text('代理地址'),
                            subtitle: Text(
                                config.proxyUrl.isEmpty ? '未设置' : config.proxyUrl,
                                style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                            onTap: () => _showProxyEditor(context, ref, config),
                        ),

                    // ===== 显示设置 =====
                    _buildSectionHeader(context, '显示设置'),
                    ListTile(
                        leading: Icon(Icons.dark_mode_outlined, color: context.appColors.accent),
                        title: const Text('主题模式'),
                        subtitle: Text(_getThemeModeLabel(config.themeMode)),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => _showThemeModePicker(context, ref, config),
                    ),
                    ListTile(
                        leading: Icon(Icons.auto_stories, color: context.appColors.accent),
                        title: const Text('默认阅读模式'),
                        subtitle: Text(_getReaderModeLabel(config.readerMode)),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => _showReaderModePicker(context, ref, config),
                    ),

                    // ===== 关于 =====
                    _buildSectionHeader(context, '关于'),
                    const _VersionTile(),
                    ListTile(
                        leading: Icon(Icons.code, color: context.appColors.accent),
                        title: const Text('下载管理'),
                        trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                        onTap: () => context.push('/downloads'),
                    ),
                ],
            ),
        );
    }

    /// 构建账号区块
    ///
    /// 未登录：显示"登录账号"入口；已登录：显示用户信息、
    /// 我的收藏入口与退出登录。
    List<Widget> _buildAccountSection(
        BuildContext context,
        WidgetRef ref,
        AuthState authState,
    )
    {
        return [
            _buildSectionHeader(context, '账号'),
            if (!authState.loggedIn)
                ListTile(
                    leading: Icon(Icons.person_outline, color: context.appColors.accent),
                    title: const Text('登录账号'),
                    subtitle: Text(
                        authState.error ?? '登录后可使用收藏功能',
                        style: TextStyle(
                            fontSize: 12,
                            color: authState.error != null
                                ? context.appColors.error
                                : context.appColors.textSecondary,
                        ),
                    ),
                    trailing: authState.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                    onTap: authState.busy ? null : () => _showLoginDialog(context, ref),
                )
            else ...[
                ListTile(
                    leading: Icon(Icons.person, color: context.appColors.accent),
                    title: Text(authState.username.isEmpty ? '已登录' : authState.username),
                    subtitle: Text(
                        '收藏 ${authState.albumFavorites} 本',
                        style: TextStyle(fontSize: 12, color: context.appColors.textSecondary),
                    ),
                ),
                ListTile(
                    leading: Icon(Icons.favorite_border, color: context.appColors.accent),
                    title: const Text('我的收藏'),
                    trailing: Icon(Icons.chevron_right, color: context.appColors.textDisabled),
                    onTap: () => context.push('/favorites'),
                ),
                ListTile(
                    leading: Icon(Icons.logout, color: context.appColors.error),
                    title: Text('退出登录', style: TextStyle(color: context.appColors.error)),
                    onTap: () => _confirmLogout(context, ref),
                ),
            ],
        ];
    }

    /// 显示登录对话框（用户名 + 密码）
    void _showLoginDialog(BuildContext context, WidgetRef ref)
    {
        final usernameController = TextEditingController();
        final passwordController = TextEditingController();
        final formKey = GlobalKey<FormState>();

        showDialog(
            context: context,
            builder: (dialogContext) => Form(
                key: formKey,
                child: AlertDialog(
                    title: const Text('登录账号'),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            TextFormField(
                                controller: usernameController,
                                decoration: const InputDecoration(
                                    labelText: '用户名',
                                    prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: '密码',
                                    prefixIcon: Icon(Icons.lock_outline),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty) ? '请输入密码' : null,
                                onFieldSubmitted: (_) =>
                                    _submitLogin(context, ref, dialogContext, formKey,
                                        usernameController, passwordController),
                            ),
                        ],
                    ),
                    actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('取消'),
                        ),
                        ElevatedButton(
                            onPressed: () => _submitLogin(context, ref, dialogContext,
                                formKey, usernameController, passwordController),
                            child: const Text('登录'),
                        ),
                    ],
                ),
            ),
        );
    }

    /// 提交登录：校验表单 → 调用 authProvider → 成功关闭对话框并提示
    Future<void> _submitLogin(
        BuildContext context,
        WidgetRef ref,
        BuildContext dialogContext,
        GlobalKey<FormState> formKey,
        TextEditingController usernameController,
        TextEditingController passwordController,
    ) async
    {
        if (!(formKey.currentState?.validate() ?? false)) return;

        final ok = await ref.read(authProvider.notifier).login(
            usernameController.text.trim(),
            passwordController.text,
        );
        if (!context.mounted) return;

        if (ok)
        {
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('登录成功')),
            );
        }
        else
        {
            // 失败：错误信息已写入 authProvider.error，对话框保持打开
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ref.read(authProvider).error ?? '登录失败')),
            );
        }
    }

    /// 确认退出登录
    void _confirmLogout(BuildContext context, WidgetRef ref)
    {
        showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
                title: const Text('退出登录'),
                content: const Text('确定要退出当前账号吗？'),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消'),
                    ),
                    TextButton(
                        onPressed: ()
                        {
                            Navigator.pop(dialogContext);
                            ref.read(authProvider.notifier).logout();
                        },
                        child: Text('退出', style: TextStyle(color: context.appColors.error)),
                    ),
                ],
            ),
        );
    }

    /// 构建分组标题
    Widget _buildSectionHeader(BuildContext context, String title)
    {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
                title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.accent,
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
                                    Icon(Icons.check, color: context.appColors.accent, size: 20),
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
                                    Icon(Icons.check, color: context.appColors.accent, size: 20),
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
                                    Icon(Icons.check, color: context.appColors.accent, size: 20),
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
                                    Icon(Icons.check, color: context.appColors.accent, size: 20),
                            ],
                        ),
                    ),
                ).toList(),
            ),
        );
    }
}

/// 关于页"版本"项
/// 从 [AppVersion] 常量读取版本号（构建时通过 --dart-define 注入）
class _VersionTile extends StatelessWidget
{
    const _VersionTile();

    @override
    Widget build(BuildContext context)
    {
        return ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.accent),
            title: const Text('版本'),
            subtitle: Text(
                AppVersion.displayLabel,
                style: const TextStyle(fontSize: 12),
            ),
        );
    }
}
