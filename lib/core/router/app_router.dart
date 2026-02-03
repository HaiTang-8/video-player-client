import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/models.dart';
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
import '../../screens/storages/resources_screen.dart';
import '../../screens/storages/storage_browse_screen.dart';
import '../../screens/library/category_detail_screen.dart';
import '../../screens/library/watch_history_screen.dart';
import '../../screens/playback_settings/playback_settings_screen.dart';
import '../../screens/settings/database_backup_screen.dart';
import '../../screens/settings/aria2_settings_screen.dart';
import '../../screens/settings/storage_management_screen.dart';
import '../../screens/settings/log_viewer_screen.dart';
import '../../screens/tvshow_detail/overview_screen.dart';
import '../../screens/download/download_episodes_screen.dart';
import '../../screens/download/download_manager_screen.dart';
import '../../screens/connection_error/connection_error_screen.dart';

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
      final isError = connectionState == ServerConnectionState.error;
      final isOnConfigPage = state.matchedLocation == '/config';
      final isOnErrorPage = state.matchedLocation == '/connection-error';

      // 如果未配置服务器且不在配置页面，跳转到配置页面
      if (!isConfigured && !isOnConfigPage) {
        return '/config';
      }

      // 如果已配置但连接失败，跳转到错误页面
      if (isConfigured && isError && !isOnErrorPage && !isOnConfigPage) {
        return '/connection-error';
      }

      // 如果已配置且在配置页面且已连接，跳转到媒体库
      if (isConfigured && isOnConfigPage && isConnected) {
        return '/library';
      }

      // 如果在错误页面但已连接，跳转到媒体库
      if (isOnErrorPage && isConnected) {
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

      // 连接错误页面（不在 Shell 内）
      GoRoute(
        path: '/connection-error',
        builder: (context, state) => const ConnectionErrorScreen(),
      ),

      // 主 Shell 路由（带底部导航栏）
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // 媒体库
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LibraryScreen(),
            ),
          ),

          // 资源库（存储管理）
          GoRoute(
            path: '/storages',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ResourcesScreen(),
            ),
            routes: [
              // 存储源目录浏览
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = int.parse(state.pathParameters['id']!);
                  final extra = state.extra;
                  final storage = extra is Storage
                      ? extra
                      : (extra is Map<String, dynamic>
                          ? Storage.fromJson(extra)
                          : null);
                  return StorageBrowseScreen(storageId: id, storage: storage);
                },
              ),
            ],
          ),

          // 我的
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
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
          final extra = state.extra as Map<String, dynamic>?;
          final position = extra?['position'] as int? ??
              int.tryParse(state.uri.queryParameters['position'] ?? '');
          final title = extra?['title'] as String? ??
              state.uri.queryParameters['title'];
          return PlayerScreen(type: 'movie', id: id, initialPosition: position, title: title);
        },
      ),

      // 剧集播放器
      GoRoute(
        path: '/player/episode/:tvShowId/:seasonId/:episodeId',
        builder: (context, state) {
          final tvShowId = int.parse(state.pathParameters['tvShowId']!);
          final seasonId = int.parse(state.pathParameters['seasonId']!);
          final episodeId = int.parse(state.pathParameters['episodeId']!);
          final extra = state.extra as Map<String, dynamic>?;
          final position = extra?['position'] as int? ??
              int.tryParse(state.uri.queryParameters['position'] ?? '');
          final title = extra?['title'] as String? ??
              state.uri.queryParameters['title'];
          final episodesRaw = extra?['episodes'];
          final episodes = episodesRaw is List
              ? episodesRaw.whereType<Episode>().toList()
              : null;
          return PlayerScreen(
            type: 'episode',
            id: episodeId,
            tvShowId: tvShowId,
            seasonId: seasonId,
            initialPosition: position,
            title: title,
            episodes: episodes,
          );
        },
      ),

      // 搜索页面
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // 分类详情页面
      GoRoute(
        path: '/category/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final name = state.uri.queryParameters['name'] ?? '';
          return CategoryDetailScreen(categoryId: id, categoryName: name);
        },
      ),

      // 观看历史页面
      GoRoute(
        path: '/watch-history',
        builder: (context, state) => const WatchHistoryScreen(),
      ),

      // 设置页面
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // 存储源管理页面（从设置进入，不在 Shell 内）
      GoRoute(
        path: '/storage-manage',
        builder: (context, state) => const StoragesScreen(),
      ),

      // 播放设置页面
      GoRoute(
        path: '/playback-settings',
        builder: (context, state) => const PlaybackSettingsScreen(),
      ),

      // 数据库备份页面
      GoRoute(
        path: '/database-backup',
        builder: (context, state) => const DatabaseBackupScreen(),
      ),

      // aria2 设置页面
      GoRoute(
        path: '/aria2-settings',
        builder: (context, state) => const Aria2SettingsScreen(),
      ),

      // 存储空间管理页面
      GoRoute(
        path: '/storage-management',
        builder: (context, state) => const StorageManagementScreen(),
      ),

      // 日志查看页面
      GoRoute(
        path: '/log-viewer',
        builder: (context, state) => const LogViewerScreen(),
      ),

      // 服务器管理页面（从设置进入）
      GoRoute(
        path: '/server-config',
        builder: (context, state) => const ServerConfigScreen(),
      ),

      // 剧情简介页面
      GoRoute(
        path: '/overview',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OverviewScreen(
            title: extra['title'] as String,
            overview: extra['overview'] as String,
          );
        },
      ),

      // 下载选择页面
      GoRoute(
        path: '/download-episodes',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final seasonData = extra['season'];
          final season = seasonData is Season
              ? seasonData
              : Season.fromJson(seasonData as Map<String, dynamic>);
          return DownloadEpisodesScreen(
            tvShowName: extra['tvShowName'] as String,
            seasonNumber: extra['seasonNumber'] as int,
            season: season,
            storageName: extra['storageName'] as String?,
          );
        },
      ),

      // 下载管理页面
      GoRoute(
        path: '/download-manager',
        builder: (context, state) => const DownloadManagerScreen(),
      ),
    ],
    errorBuilder:
        (context, state) => Scaffold(
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
