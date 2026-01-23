import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/smooth_scroll_behavior.dart';
import 'core/widgets/ios_ui_utils.dart';
import 'data/services/aria2_manager.dart';
import 'data/services/log_service.dart';
import 'data/services/update_service.dart';
import 'providers/providers.dart';
import 'providers/error_notification_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志服务
  await LogService.instance.init();

  // 初始化 MediaKit
  MediaKit.ensureInitialized();

  // 初始化 SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // PC端自动启动aria2
  if (Platform.isWindows || Platform.isMacOS) {
    final engine = prefs.getString(AppConstants.downloadEngineKey) ?? 'aria2Builtin';
    if (engine == 'aria2Builtin') {
      _initAria2();
    }
  }

  // 初始化更新服务（macOS Sparkle）
  await UpdateService.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MediaPlayerApp(),
    ),
  );
}

Future<void> _initAria2() async {
  final aria2 = Aria2Manager.instance;
  if (aria2.isRunning) return;
  try {
    await aria2.ensureBinary();
    await aria2.start();
  } catch (_) {}
}

class MediaPlayerApp extends ConsumerStatefulWidget {
  const MediaPlayerApp({super.key});

  @override
  ConsumerState<MediaPlayerApp> createState() => _MediaPlayerAppState();
}

class _MediaPlayerAppState extends ConsumerState<MediaPlayerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serverConnectionProvider.notifier).connectToSavedServer();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Aria2Manager.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      Aria2Manager.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    ref.listen<String?>(errorNotificationProvider, (_, error) {
      if (error != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navigatorState = router.routerDelegate.navigatorKey.currentState;
          if (navigatorState?.overlay != null) {
            IosUiUtils.showToastWithOverlay(
              overlay: navigatorState!.overlay!,
              message: error,
              isError: true,
            );
          }
        });
      }
    });

    return MaterialApp.router(
      title: 'Media Player',
      debugShowCheckedModeBanner: false,
      scrollBehavior: SmoothScrollBehavior(),
      actions: {
        ...WidgetsApp.defaultActions,
        ScrollIntent: AnimatedScrollAction(),
      },
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
