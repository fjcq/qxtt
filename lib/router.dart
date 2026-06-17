import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pages/home_page.dart';
import '../pages/history_page.dart';
import '../pages/search_page.dart';
import '../pages/album_detail_page.dart';
import '../pages/online_reader_page.dart';
import '../pages/reader_page.dart';
import '../pages/download_page.dart';
import '../pages/settings_page.dart';
import '../pages/domain_management_page.dart';

/// 应用路由配置
final routerProvider = Provider<GoRouter>((ref)
{
    return GoRouter(
        initialLocation: '/',
        routes: [
            // 底部导航的 Shell 路由
            ShellRoute(
                builder: (context, state, child)
                {
                    return _AppShell(child: child);
                },
                routes: [
                    GoRoute(
                        path: '/',
                        name: 'home',
                        builder: (context, state) => const HomePage(),
                    ),
                    GoRoute(
                        path: '/history',
                        name: 'history',
                        builder: (context, state) => const HistoryPage(),
                    ),
                    GoRoute(
                        path: '/downloads',
                        name: 'downloads',
                        builder: (context, state) => const DownloadPage(),
                    ),
                    GoRoute(
                        path: '/settings',
                        name: 'settings',
                        builder: (context, state) => const SettingsPage(),
                    ),
                ],
            ),
            // 全屏页面（不在底部导航内）
            GoRoute(
                path: '/search',
                name: 'search',
                builder: (context, state) => const SearchPage(),
            ),
            GoRoute(
                path: '/album/:id',
                name: 'album',
                builder: (context, state)
                {
                    final albumId = state.pathParameters['id']!;
                    return AlbumDetailPage(albumId: albumId);
                },
            ),
            GoRoute(
                path: '/reader/:photoId',
                name: 'reader',
                builder: (context, state)
                {
                    final photoId = state.pathParameters['photoId']!;
                    return ReaderPage(photoId: photoId);
                },
            ),
            GoRoute(
                path: '/reader/online/:photoId',
                name: 'reader-online',
                builder: (context, state)
                {
                    final photoId = state.pathParameters['photoId']!;
                    return OnlineReaderPage(photoId: photoId);
                },
            ),
            GoRoute(
                path: '/settings/domains',
                name: 'settings-domains',
                builder: (context, state) => const DomainManagementPage(),
            ),
        ],
    );
});

/// 应用外壳（底部导航栏）
class _AppShell extends StatelessWidget
{
    final Widget child;

    const _AppShell({required this.child});

    @override
    Widget build(BuildContext context)
    {
        return Scaffold(
            body: child,
            bottomNavigationBar: _buildBottomNav(context),
        );
    }

    /// 构建底部导航栏
    Widget _buildBottomNav(BuildContext context)
    {
        final currentPath = GoRouterState.of(context).matchedLocation;

        int currentIndex = 0;
        if (currentPath.startsWith('/history'))
        {
            currentIndex = 1;
        }
        else if (currentPath.startsWith('/downloads'))
        {
            currentIndex = 2;
        }
        else if (currentPath.startsWith('/settings'))
        {
            currentIndex = 3;
        }

        return NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index)
            {
                switch (index)
                {
                    case 0:
                        context.go('/');
                        break;
                    case 1:
                        context.go('/history');
                        break;
                    case 2:
                        context.go('/downloads');
                        break;
                    case 3:
                        context.go('/settings');
                        break;
                }
            },
            destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore),
                    label: '首页',
                ),
                NavigationDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history),
                    label: '历史',
                ),
                NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    selectedIcon: Icon(Icons.download),
                    label: '下载',
                ),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: '设置',
                ),
            ],
        );
    }
}
