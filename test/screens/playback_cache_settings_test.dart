import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/constants/app_constants.dart';
import 'package:media_player/playback/cache/playback_cache_catalog.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/providers/playback_settings_provider.dart';
import 'package:media_player/providers/server_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_test_app.dart';

CachedVideo _video(
  String id,
  String name,
  int cached,
  int size,
  int hoursAgo,
) => CachedVideo(
  id: id,
  name: name,
  cachedBytes: cached,
  sizeBytes: size,
  lastAccess: DateTime.now().subtract(Duration(hours: hoursAgo)),
);

void main() {
  late SharedPreferences prefs;
  late FakePlaybackCacheCatalog catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    catalog = FakePlaybackCacheCatalog();
  });

  group('cache quota setting', () {
    ProviderContainer container({bool supported = true}) {
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          playbackCacheCatalogProvider.overrideWithValue(catalog),
          playbackCacheSupportedProvider.overrideWithValue(supported),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('defaults per platform and ignores unknown stored values', () async {
      expect(
        container().read(playbackSettingsProvider).cacheQuotaGb,
        PlaybackCacheConfig.defaultQuotaGb,
      );
      await prefs.setInt(AppConstants.playbackCacheQuotaGbKey, 7);
      expect(
        container().read(playbackSettingsProvider).cacheQuotaGb,
        PlaybackCacheConfig.defaultQuotaGb,
      );
      await prefs.setInt(AppConstants.playbackCacheQuotaGbKey, 0);
      expect(container().read(playbackSettingsProvider).cacheQuotaGb, 0);
    });

    test('persists the quota and applies it to the cache at once', () async {
      final c = container();
      await c.read(playbackSettingsProvider.notifier).setCacheQuotaGb(5);
      expect(c.read(playbackSettingsProvider).cacheQuotaGb, 5);
      expect(prefs.getInt(AppConstants.playbackCacheQuotaGbKey), 5);
      expect(catalog.quotas, [5 << 30]);

      await c.read(playbackSettingsProvider.notifier).setCacheQuotaGb(3);
      expect(c.read(playbackSettingsProvider).cacheQuotaGb, 5);
      expect(catalog.quotas, [5 << 30]);
    });

    test('does not touch the cache where it is not supported', () async {
      final c = container(supported: false);
      await c.read(playbackSettingsProvider.notifier).setCacheQuotaGb(0);
      expect(prefs.getInt(AppConstants.playbackCacheQuotaGbKey), 0);
      expect(catalog.quotas, isEmpty);
    });
  });

  group('playback settings section', () {
    testWidgets('shows the quota and usage and turns the cache off', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      catalog.videos = [_video('a', 'a.mkv', 300 << 20, 1 << 30, 1)];
      await tester.pumpWidget(
        buildSettingsTestApp(prefs: prefs, catalog: catalog),
      );
      await tester.pumpAndSettle();

      expect(find.text('播放缓存'), findsOneWidget);
      expect(
        find.text('${PlaybackCacheConfig.defaultQuotaGb} GB'),
        findsOneWidget,
      );
      expect(find.text('300.0 MB'), findsOneWidget);

      await tester.tap(find.text('缓存上限'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(catalog.quotas, [0]);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('0 B'), findsOneWidget);
    });
  });

  group('cache detail screen', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      await tester.pumpWidget(
        buildSettingsTestApp(
          prefs: prefs,
          catalog: catalog,
          initialLocation: '/video-cache-detail',
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists cached videos with their state', (tester) async {
      catalog.videos = [
        _video(
          'a',
          'A.Very.Long.Movie.Name.2160p.WEB-DL.DV.HDR10.DTS.mkv',
          500 << 20,
          4 << 30,
          2,
        ),
        _video('b', 'b.mp4', 1 << 20, 1 << 20, 30),
      ];
      await pumpDetail(tester);

      expect(find.text('501.0 MB'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);
      expect(
        find.textContaining('500.0 MB / 4.00 GB · 部分 · 2小时前'),
        findsOneWidget,
      );
      expect(find.textContaining('1.0 MB · 完整 · 1天前'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '长文件名不应溢出');
    });

    testWidgets('shows the empty state', (tester) async {
      await pumpDetail(tester);
      expect(find.text('暂无播放缓存'), findsOneWidget);
      expect(find.textContaining('清除全部缓存'), findsNothing);
    });

    testWidgets('shows an error with retry', (tester) async {
      catalog.error = StateError('proxy down');
      await pumpDetail(tester);
      expect(find.text('无法读取播放缓存，请稍后重试'), findsOneWidget);

      catalog
        ..error = null
        ..videos = [_video('a', 'a.mkv', 1024, 2048, 1)];
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('a.mkv'), findsOneWidget);
    });

    testWidgets('deletes one entry after confirming', (tester) async {
      catalog.videos = [
        _video('a', 'a.mkv', 1024, 2048, 1),
        _video('b', 'b.mkv', 1024, 2048, 1),
      ];
      await pumpDetail(tester);

      await tester.tap(find.text('a.mkv'));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定要删除「a.mkv」的缓存吗'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(catalog.removed, ['a']);
      expect(find.text('a.mkv'), findsNothing);
      expect(find.text('b.mkv'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });
  });
}
