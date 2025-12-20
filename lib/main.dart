import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 MediaKit
  MediaKit.ensureInitialized();

  // 初始化 SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MediaPlayerApp(),
    ),
  );
}

class MediaPlayerApp extends ConsumerStatefulWidget {
  const MediaPlayerApp({super.key});

  @override
  ConsumerState<MediaPlayerApp> createState() => _MediaPlayerAppState();
}

class _MediaPlayerAppState extends ConsumerState<MediaPlayerApp> {
  @override
  void initState() {
    super.initState();
    // 尝试连接到已保存的服务器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serverConnectionProvider.notifier).connectToSavedServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Media Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
