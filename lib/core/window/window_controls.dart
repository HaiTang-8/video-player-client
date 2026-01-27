import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowControls {
  WindowControls._();

  static const MethodChannel _channel =
      MethodChannel('media_player/window_controls');

  /// 是否为桌面平台（Windows/macOS）
  /// 注意：不包含 Linux，因为本项目没有 Linux 原生窗口控制实现
  /// 如需纯 Dart 的桌面判断（如平滑滚动），请使用 DesktopSmoothScroll.isDesktop
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> startDrag() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod<void>('startDrag');
    } on PlatformException {
      // Ignore if not supported on the current platform.
    } on MissingPluginException {
      // Ignore in tests or unsupported platforms.
    }
  }

  static Future<void> minimize() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod<void>('minimize');
    } on PlatformException {
      // Ignore if not supported on the current platform.
    } on MissingPluginException {
      // Ignore in tests or unsupported platforms.
    }
  }

  static Future<void> toggleMaximize() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod<void>('toggleMaximize');
    } on PlatformException {
      // Ignore if not supported on the current platform.
    } on MissingPluginException {
      // Ignore in tests or unsupported platforms.
    }
  }

  static Future<void> close() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // Ignore if not supported on the current platform.
    } on MissingPluginException {
      // Ignore in tests or unsupported platforms.
    }
  }

  static Future<void> toggleFullscreen() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod<void>('toggleFullscreen');
    } on PlatformException {
      // Ignore if not supported on the current platform.
    } on MissingPluginException {
      // Ignore in tests or unsupported platforms.
    }
  }

  static Future<bool> isFullscreen() async {
    if (!isDesktop) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isFullscreen');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isMaximized() async {
    if (!isDesktop) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isMaximized');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

