import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/core/theme/app_theme.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/native/native_playback_engine.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/screens/player/widgets/custom_video_controls.dart';
import 'package:media_player/screens/player/widgets/player_top_bar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// 不短于 60 秒、带中文字幕的本地样片
const _samplePath = String.fromEnvironment('NATIVE_PLAYER_GESTURE_SAMPLE');

/// 手动驱动的验证：真实触摸经过原生 PlatformView 时 Flutter 控制层是否正常，以及 iOS 前后台恢复。
/// 每一步打印 `NP_STEP <名称>` 后等待操作者在设备上完成对应操作：
/// tap 单击画面；longpress 长按 2 秒以上；swipe 从左向右横滑；
/// background 回到主屏幕再切回 App；landscape、resumed 打印 NP_HOLD 供截图
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'controls respond to real touches over the native view',
    (tester) async {
      binding.shouldPropagateDevicePointerEvents = true;
      final lifecycle = _LifecycleRecorder();
      WidgetsBinding.instance.addObserver(lifecycle);
      final engine = NativePlaybackEngine(
        kind: PlaybackEngineKind.aether,
        initialCapabilities: const EngineCapabilities(
          dolbyVisionColor: true,
          maxVolume: 1.0,
          maxRate: 2.0,
        ),
        subtitleFontAssets: subtitleFontAssets,
      );
      final errors = <PlaybackError>[];
      final errorSubscription = engine.streams.errors.listen(errors.add);
      await engine.initialize();
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          theme: AppTheme.shadcnDarkTheme,
          home: Scaffold(
            backgroundColor: Colors.black,
            body: CustomVideoControls(
              engine: engine,
              title: '手势验证',
              longPressSpeed: 2.0,
            ),
          ),
        ),
      );
      await engine.open(const PlaybackSource.localFile(_samplePath));
      await _waitFor(
        tester,
        'tracks',
        () => engine.state.tracks.subtitle.isNotEmpty,
      );
      await engine.selectSubtitleTrack(engine.state.tracks.subtitle.first);
      await _waitFor(
        tester,
        'playback',
        () => engine.state.position > const Duration(seconds: 1),
      );

      await _waitFor(
        tester,
        'controls hidden',
        () => find.byType(PlayerTopBar).evaluate().isEmpty,
      );
      _step('tap');
      await _waitFor(
        tester,
        'tap',
        () => find.byType(PlayerTopBar).evaluate().isNotEmpty,
      );

      _step('longpress');
      await _waitFor(tester, 'long press', () => engine.state.rate == 2.0);
      await _waitFor(tester, 'long press end', () => engine.state.rate == 1.0);

      await engine.pause();
      await _waitFor(tester, 'pause', () => !engine.state.playing);
      final beforeSwipe = engine.state.position;
      _step('swipe');
      await _waitFor(
        tester,
        'swipe',
        () => engine.state.position - beforeSwipe > const Duration(seconds: 5),
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await _settle(tester, const Duration(seconds: 2));
      debugPrint('NP_HOLD landscape');
      await _settle(tester, const Duration(seconds: 6));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await _settle(tester, const Duration(seconds: 2));

      await engine.play();
      await _waitFor(tester, 'play', () => engine.state.playing);
      final beforeBackground = engine.state.position;
      _step('background');
      await _waitFor(
        tester,
        'background',
        () => lifecycle.wentToBackground && lifecycle.resumed,
      );
      // 回到前台保持暂停，重建后从原位置继续
      await _settle(tester, const Duration(seconds: 3));
      expect(engine.state.playing, isFalse);
      expect(engine.state.position, greaterThanOrEqualTo(beforeBackground));
      await engine.play();
      await _waitFor(
        tester,
        'resume',
        () =>
            engine.state.playing &&
            engine.state.position >
                beforeBackground + const Duration(seconds: 1),
      );
      // 软解路径从新位置重建后要等下一个关键帧才有画面
      await _settle(tester, const Duration(seconds: 6));
      debugPrint('NP_HOLD resumed');
      await _settle(tester, const Duration(seconds: 6));
      await SystemChrome.setPreferredOrientations([]);

      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await errorSubscription.cancel();
      await engine.dispose();
      WidgetsBinding.instance.removeObserver(lifecycle);
      binding.shouldPropagateDevicePointerEvents = false;
    },
    skip: _samplePath.isEmpty,
  );
}

class _LifecycleRecorder with WidgetsBindingObserver {
  bool wentToBackground = false;
  bool resumed = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) wentToBackground = true;
    if (state == AppLifecycleState.resumed && wentToBackground) resumed = true;
  }
}

void _step(String name) => debugPrint('NP_STEP $name');

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 等待操作者完成操作，最长 3 分钟
Future<void> _waitFor(
  WidgetTester tester,
  String what,
  bool Function() condition,
) async {
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $what');
}
