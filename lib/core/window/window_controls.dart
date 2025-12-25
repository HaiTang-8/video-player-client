import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowControls {
  WindowControls._();

  static const MethodChannel _channel =
      MethodChannel('media_player/window_controls');

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
}

