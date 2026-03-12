import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class DetailBackgroundPalette {
  DetailBackgroundPalette._();

  static final Map<String, Color> _cache = <String, Color>{};
  static final Map<String, Future<Color>> _inFlight = <String, Future<Color>>{};

  static Color? getCached(String cacheKey) => _cache[cacheKey];

  static Future<Color> resolve(
    String cacheKey, {
    required ImageProvider provider,
    required Color fallbackColor,
  }) {
    final cached = _cache[cacheKey];
    if (cached != null) {
      return Future.value(cached);
    }

    final pending = _inFlight[cacheKey];
    if (pending != null) {
      return pending;
    }

    final future = _extract(
      provider: provider,
      fallbackColor: fallbackColor,
    ).then((color) {
      _cache[cacheKey] = color;
      _inFlight.remove(cacheKey);
      return color;
    });

    _inFlight[cacheKey] = future;
    return future;
  }

  static Future<Color> _extract({
    required ImageProvider provider,
    required Color fallbackColor,
  }) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(96, 144),
        maximumColorCount: 20,
      );

      final candidate =
          palette.darkMutedColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          fallbackColor;

      return _normalize(candidate, fallbackColor);
    } catch (_) {
      return fallbackColor;
    }
  }

  static Color _normalize(Color source, Color fallbackColor) {
    final opaque = source.withValues(alpha: 1);
    final hsl = HSLColor.fromColor(opaque);
    final adjusted = hsl
        .withSaturation(math.min(hsl.saturation * 0.85, 0.55))
        .withLightness(_clampDouble(hsl.lightness, 0.10, 0.22));

    var result =
        Color.lerp(adjusted.toColor(), fallbackColor, 0.18) ?? fallbackColor;

    while (_contrastRatio(result, Colors.white) < 4.8) {
      final darkened = HSLColor.fromColor(result).withLightness(
        math.max(HSLColor.fromColor(result).lightness - 0.04, 0.06),
      );
      if (darkened.toColor() == result) {
        break;
      }
      result = darkened.toColor();
    }

    return result;
  }

  static double _contrastRatio(Color a, Color b) {
    final luminanceA = a.computeLuminance();
    final luminanceB = b.computeLuminance();
    final lighter = math.max(luminanceA, luminanceB);
    final darker = math.min(luminanceA, luminanceB);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _clampDouble(double value, double minValue, double maxValue) {
    if (value < minValue) {
      return minValue;
    }
    if (value > maxValue) {
      return maxValue;
    }
    return value;
  }
}
