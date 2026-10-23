import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/core/localization/shadcn_zh_localizations.dart';
import 'package:media_player/core/theme/app_theme.dart';
import 'package:media_player/playback/cache/playback_cache_catalog.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/providers/server_provider.dart';
import 'package:media_player/screens/playback_settings/playback_settings_screen.dart';
import 'package:media_player/screens/playback_settings/video_cache_detail_screen.dart';
import 'package:media_player/screens/settings/storage_management_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:shared_preferences/shared_preferences.dart';

/// 可控的播放缓存目录
class FakePlaybackCacheCatalog implements PlaybackCacheCatalog {
  List<CachedVideo> videos = [];
  Object? error;
  final List<int> quotas = [];
  final List<String> removed = [];
  int clears = 0;

  @override
  Future<List<CachedVideo>> entries() async {
    final failure = error;
    if (failure != null) throw failure;
    return List.of(videos);
  }

  @override
  Future<int> usedBytes() async {
    final failure = error;
    if (failure != null) throw failure;
    return videos.fold<int>(0, (sum, v) => sum + v.cachedBytes);
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    videos.removeWhere((v) => v.id == id);
  }

  @override
  Future<void> clearCache() async {
    clears++;
    videos = [];
  }

  @override
  Future<void> setQuota(int bytes) async {
    quotas.add(bytes);
    if (bytes == 0) videos = [];
  }
}

/// 与 main.dart 相同的 shadcn + Material 主题和本地化，路由只包含播放设置、缓存明细与存储空间。
/// [captureKey] 用于把整个应用（含弹窗）渲染成图片
Widget buildSettingsTestApp({
  required SharedPreferences prefs,
  required PlaybackCacheCatalog catalog,
  String initialLocation = '/playback-settings',
  bool dark = false,
  GlobalKey? captureKey,
  GoRouter? router,
}) {
  router ??= GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      GoRoute(
        path: '/playback-settings',
        builder: (context, state) => const PlaybackSettingsScreen(),
      ),
      GoRoute(
        path: '/video-cache-detail',
        builder: (context, state) => const VideoCacheDetailScreen(),
      ),
      GoRoute(
        path: '/storage-management',
        builder: (context, state) => const StorageManagementScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      playbackCacheCatalogProvider.overrideWithValue(catalog),
      playbackCacheSupportedProvider.overrideWithValue(true),
    ],
    child: RepaintBoundary(
      key: captureKey,
      child: shadcn.ShadcnApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.shadcnLightTheme,
        darkTheme: AppTheme.shadcnDarkTheme,
        themeMode: dark ? shadcn.ThemeMode.dark : shadcn.ThemeMode.light,
        materialTheme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        routerConfig: router,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          ShadcnZhLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
}
