import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/playback/cache/playback_cache_catalog.dart';
import 'package:media_player/screens/playback_settings/playback_settings_screen.dart';
import 'package:media_player/screens/playback_settings/video_cache_detail_screen.dart';
import 'package:media_player/screens/settings/storage_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/screens/support/settings_test_app.dart';

/// 截图写到这个目录（宿主机路径，模拟器可以直接写）
const _shotsDir = String.fromEnvironment('SHOTS_DIR');

/// Stage 5 界面自查：播放设置的缓存一节、上限滑块（开 / 关）、缓存明细（列表 / 删除确认 / 空 / 读取失败）、存储空间，浅色与深色各一套
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the playback cache screens', (tester) async {
    await Directory(_shotsDir).create(recursive: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    Future<void> shot(GlobalKey key, String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$_shotsDir/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
      debugPrint('NP_SHOT $name');
    }

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      final key = GlobalKey();
      final catalog =
          FakePlaybackCacheCatalog()
            ..videos = [
              CachedVideo(
                id: 'a',
                name:
                    'Mystic.Nine.S01E23.2026.2160p.HQ.WEB-DL.H265.DV.60fps.DTS5.1-BlackTV.mkv',
                cachedBytes: 312 << 20,
                sizeBytes: 6108410667,
                lastAccess: DateTime.now().subtract(
                  const Duration(minutes: 20),
                ),
              ),
              CachedVideo(
                id: 'b',
                name: '流浪地球2.2023.1080p.mp4',
                cachedBytes: 96 << 20,
                sizeBytes: 2 << 30,
                lastAccess: DateTime.now().subtract(const Duration(days: 3)),
              ),
              CachedVideo(
                id: 'c',
                name: 'short.mkv',
                cachedBytes: 40 << 20,
                sizeBytes: 40 << 20,
                lastAccess: DateTime.now().subtract(const Duration(days: 40)),
              ),
            ];
      final router = GoRouter(
        initialLocation: '/playback-settings',
        routes: [
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
      await tester.pumpWidget(
        buildSettingsTestApp(
          prefs: prefs,
          catalog: catalog,
          dark: dark,
          captureKey: key,
          router: router,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await shot(key, 'settings_$theme');

      await tester.tap(find.text('缓存上限'));
      await shot(key, 'quota_$theme');
      await tester.tap(find.byType(CupertinoSwitch));
      await shot(key, 'quota_off_$theme');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('已缓存'));
      await shot(key, 'detail_$theme');

      await tester.tap(find.text('流浪地球2.2023.1080p.mp4'));
      await shot(key, 'delete_$theme');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      catalog.videos = [];
      router.go('/playback-settings');
      await tester.pumpAndSettle();
      router.push('/video-cache-detail');
      await shot(key, 'empty_$theme');

      catalog.error = StateError('cache proxy is not reachable');
      router.go('/playback-settings');
      await tester.pumpAndSettle();
      router.push('/video-cache-detail');
      await shot(key, 'error_$theme');
      catalog.error = null;

      router.go('/storage-management');
      await tester.pump(const Duration(seconds: 1));
      await shot(key, 'storage_$theme');
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: _shotsDir.isEmpty);
}
