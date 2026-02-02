import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/smooth_scroll_behavior.dart';
import 'core/widgets/window_border.dart';
import 'core/widgets/dialog_utils.dart';
import 'data/services/aria2_manager.dart';
import 'data/services/log_service.dart';
import 'data/services/update_service.dart';
import 'providers/providers.dart';
import 'providers/error_notification_provider.dart';
import 'providers/watch_history_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志服务
  await LogService.instance.init();

  // 初始化 MediaKit
  MediaKit.ensureInitialized();

  // 移动端默认锁定竖屏（播放器场景除外）
  if (Platform.isIOS || Platform.isAndroid) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

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
  final serverUrl = _getCurrentServerUrl(prefs);
  await UpdateService.instance.init(serverUrl);

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

String? _getCurrentServerUrl(SharedPreferences prefs) {
  final listJson = prefs.getString(AppConstants.serverListKey);
  final currentId = prefs.getString(AppConstants.currentServerIdKey);

  if (listJson != null && currentId != null) {
    try {
      final List<dynamic> list = jsonDecode(listJson);
      for (final item in list) {
        if (item['id'] == currentId) {
          return item['url'] as String?;
        }
      }
      if (list.isNotEmpty) {
        return list.first['url'] as String?;
      }
    } catch (_) {}
  }

  return prefs.getString(AppConstants.serverUrlKey);
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
    } else if (state == AppLifecycleState.resumed) {
      ref.read(watchHistoryProvider.notifier).scheduleRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    ref.listen<String?>(errorNotificationProvider, (_, error) {
      if (error != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navigatorContext = router.routerDelegate.navigatorKey.currentContext;
          if (navigatorContext != null) {
            DialogUtils.showToast(
              context: navigatorContext,
              message: error,
              isError: true,
            );
          }
        });
      }
    });

    // 根据当前主题模式选择 Material 主题
    final effectiveThemeMode = themeMode == ThemeMode.system
        ? (WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light)
        : themeMode;
    final materialTheme = effectiveThemeMode == ThemeMode.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;

    return shadcn.ShadcnApp.router(
      title: 'Media Player',
      debugShowCheckedModeBanner: false,
      scrollBehavior: SmoothScrollBehavior(),
      theme: AppTheme.shadcnLightTheme,
      darkTheme: AppTheme.shadcnDarkTheme,
      themeMode: themeMode == ThemeMode.system
          ? shadcn.ThemeMode.system
          : (themeMode == ThemeMode.dark
              ? shadcn.ThemeMode.dark
              : shadcn.ThemeMode.light),
      materialTheme: materialTheme,
      routerConfig: router,
      popoverHandler: const shadcn.PopoverOverlayHandler(),
      menuHandler: const shadcn.PopoverOverlayHandler(),
      actions: {
        ...WidgetsApp.defaultActions,
        ScrollIntent: AnimatedScrollAction(),
      },
      builder: (context, child) => WindowBorder(child: child ?? const SizedBox()),
    );
  }
}
