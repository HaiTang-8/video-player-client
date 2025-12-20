import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/providers.dart';
import '../../screens/main_shell.dart';
import '../../screens/library/library_screen.dart';
import '../../screens/movie_detail/movie_detail_screen.dart';
import '../../screens/tvshow_detail/tvshow_detail_screen.dart';
import '../../screens/player/player_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/storages_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/server_config/server_config_screen.dart';

/// 路由刷新通知器
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    // 监听服务器 URL 变化
    ref.listen(serverUrlProvider, (_, __) => notifyListeners());
    // 监听连接状态变化
    ref.listen(serverConnectionProvider, (_, __) => notifyListeners());
  }
}

/// 路由刷新通知器 Provider
final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});

/// 路由配置 Provider
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(routerRefreshProvider);

  return GoRouter(
    initialLocation: '/library',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final serverUrl = ref.read(serverUrlProvider);
      final connectionState = ref.read(serverConnectionProvider);

      final isConfigured = serverUrl != null && serverUrl.isNotEmpty;
      final isConnected = connectionState == ServerConnectionState.connected;
      final isOnConfigPage = state.matchedLocation == '/config';

      // 如果未配置服务器且不在配置页面，跳转到配置页面
      if (!isConfigured && !isOnConfigPage) {
        return '/config';
      }

      // 如果已配置且在配置页面且已连接，跳转到媒体库
      if (isConfigured && isOnConfigPage && isConnected) {
        return '/library';
      }

      return null;
    },
    routes: [
      // 服务器配置页面（不在 Shell 内）
      GoRoute(
        path: '/config',
        builder: (context, state) => const ServerConfigScreen(),
      ),

      // 主 Shell 路由（带底部导航栏）
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // 媒体库
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const LibraryScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),

          // 资源库（存储管理）
          GoRoute(
            path: '/storages',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const StoragesScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),

          // 我的
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ProfileScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
        ],
      ),

      // 以下页面在 Shell 外部（不显示底部导航栏）

      // 电影详情
      GoRoute(
        path: '/movie/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return MovieDetailScreen(movieId: id);
        },
      ),

      // 剧集详情
      GoRoute(
        path: '/tvshow/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return TvShowDetailScreen(tvShowId: id);
        },
      ),

      // 电影播放器
      GoRoute(
        path: '/player/movie/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return PlayerScreen(type: 'movie', id: id);
        },
      ),

      // 剧集播放器
      GoRoute(
        path: '/player/episode/:tvShowId/:seasonId/:episodeId',
        builder: (context, state) {
          final tvShowId = int.parse(state.pathParameters['tvShowId']!);
          final seasonId = int.parse(state.pathParameters['seasonId']!);
          final episodeId = int.parse(state.pathParameters['episodeId']!);
          return PlayerScreen(
            type: 'episode',
            id: episodeId,
            tvShowId: tvShowId,
            seasonId: seasonId,
          );
        },
      ),

      // 搜索页面
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // 设置页面
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            Text('页面不存在: ${state.matchedLocation}'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/library'),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    ),
  );
});
