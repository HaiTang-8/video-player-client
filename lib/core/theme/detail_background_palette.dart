import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../data/services/log_service.dart';

enum DetailBackgroundPaletteMode { fullImage, posterBottom }

typedef _PaletteCandidate = ({Color? color, String source});
typedef _NormalizationResult =
    ({
      Color adjustedColor,
      Color blendedColor,
      int darkenSteps,
      double finalContrast,
      double initialContrast,
      Color result,
    });

class DetailBackgroundPalette {
  DetailBackgroundPalette._();

  static const String _logTag = 'DetailBackgroundPalette';
  static const Size _sampleSize = Size(96, 144);
  static const double _posterBottomRegionStart = 0.68;
  static final Map<String, Color> _cache = <String, Color>{};
  static final Map<String, Future<Color>> _inFlight = <String, Future<Color>>{};

  static String buildCacheKey(
    String sourceKey, {
    DetailBackgroundPaletteMode mode = DetailBackgroundPaletteMode.fullImage,
  }) => '${mode.name}::$sourceKey';

  static Color? getCached(
    String cacheKey, {
    DetailBackgroundPaletteMode mode = DetailBackgroundPaletteMode.fullImage,
  }) => _cache[buildCacheKey(cacheKey, mode: mode)];

  static Future<Color> resolve(
    String cacheKey, {
    required ImageProvider provider,
    required Color fallbackColor,
    DetailBackgroundPaletteMode mode = DetailBackgroundPaletteMode.fullImage,
    String? debugContext,
  }) {
    final resolvedCacheKey = buildCacheKey(cacheKey, mode: mode);
    final region = _regionFor(mode);
    final cached = _cache[resolvedCacheKey];
    if (cached != null) {
      _debug(
        'cache-hit mode=${mode.name} cacheKey=$resolvedCacheKey '
        'region=${_formatRect(region)} result=${_formatColor(cached)}'
        '${_contextText(debugContext)}',
      );
      return Future.value(cached);
    }

    final pending = _inFlight[resolvedCacheKey];
    if (pending != null) {
      _debug(
        'join-inflight mode=${mode.name} cacheKey=$resolvedCacheKey '
        'region=${_formatRect(region)}${_contextText(debugContext)}',
      );
      return pending;
    }

    _debug(
      'resolve-start mode=${mode.name} cacheKey=$resolvedCacheKey '
      'region=${_formatRect(region)} fallback=${_formatColor(fallbackColor)}'
      '${_contextText(debugContext)}',
    );

    final future = _extract(
      provider: provider,
      fallbackColor: fallbackColor,
      mode: mode,
      debugContext: debugContext,
    ).then((color) {
      _cache[resolvedCacheKey] = color;
      _inFlight.remove(resolvedCacheKey);
      _debug(
        'resolve-done mode=${mode.name} cacheKey=$resolvedCacheKey '
        'result=${_formatColor(color)}${_contextText(debugContext)}',
      );
      return color;
    });

    _inFlight[resolvedCacheKey] = future;
    return future;
  }

  static Future<Color> _extract({
    required ImageProvider provider,
    required Color fallbackColor,
    required DetailBackgroundPaletteMode mode,
    String? debugContext,
  }) async {
    final region = _regionFor(mode);
    try {
      final palette = await _generatePalette(provider, mode: mode);
      _debug(
        'palette-ready mode=${mode.name} region=${_formatRect(region)} '
        'palette=${_describePalette(palette)}${_contextText(debugContext)}',
      );
      final candidate = _pickCandidate(palette, mode: mode);
      if (candidate.color != null) {
        return _logAndNormalize(
          candidate.color!,
          fallbackColor,
          mode: mode,
          sourceLabel: candidate.source,
          stage: 'primary',
          debugContext: debugContext,
        );
      }

      if (mode != DetailBackgroundPaletteMode.fullImage) {
        _debug(
          'candidate-miss mode=${mode.name} region=${_formatRect(region)} '
          'retry=fullImage${_contextText(debugContext)}',
        );
        final fullImagePalette = await _generatePalette(
          provider,
          mode: DetailBackgroundPaletteMode.fullImage,
        );
        _debug(
          'palette-ready mode=${DetailBackgroundPaletteMode.fullImage.name} '
          'region=${_formatRect(_regionFor(DetailBackgroundPaletteMode.fullImage))} '
          'palette=${_describePalette(fullImagePalette)}'
          '${_contextText(debugContext)}',
        );
        final fullImageCandidate = _pickCandidate(
          fullImagePalette,
          mode: DetailBackgroundPaletteMode.fullImage,
        );
        if (fullImageCandidate.color != null) {
          return _logAndNormalize(
            fullImageCandidate.color!,
            fallbackColor,
            mode: DetailBackgroundPaletteMode.fullImage,
            sourceLabel: fullImageCandidate.source,
            stage: 'fallback-full-image',
            debugContext: debugContext,
          );
        }
      }

      _debug(
        'fallback-color mode=${mode.name} reason=no-candidate '
        'result=${_formatColor(fallbackColor)}${_contextText(debugContext)}',
      );
      return fallbackColor;
    } catch (error) {
      _debug(
        'fallback-color mode=${mode.name} reason=exception error=$error '
        'result=${_formatColor(fallbackColor)}${_contextText(debugContext)}',
      );
      return fallbackColor;
    }
  }

  static Future<PaletteGenerator> _generatePalette(
    ImageProvider provider, {
    required DetailBackgroundPaletteMode mode,
  }) {
    return PaletteGenerator.fromImageProvider(
      provider,
      size: _sampleSize,
      region: _regionFor(mode),
      maximumColorCount: 20,
    );
  }

  static Rect? _regionFor(DetailBackgroundPaletteMode mode) {
    if (mode != DetailBackgroundPaletteMode.posterBottom) {
      return null;
    }
    final top = _sampleSize.height * _posterBottomRegionStart;
    return Rect.fromLTWH(0, top, _sampleSize.width, _sampleSize.height - top);
  }

  static _PaletteCandidate _pickCandidate(
    PaletteGenerator palette, {
    required DetailBackgroundPaletteMode mode,
  }) {
    final colors = palette.colors;
    if (mode == DetailBackgroundPaletteMode.posterBottom) {
      return _firstCandidate(<_PaletteCandidate>[
        (source: 'dominantColor', color: palette.dominantColor?.color),
        (source: 'mutedColor', color: palette.mutedColor?.color),
        (source: 'vibrantColor', color: palette.vibrantColor?.color),
        (source: 'darkMutedColor', color: palette.darkMutedColor?.color),
        (source: 'darkVibrantColor', color: palette.darkVibrantColor?.color),
        (
          source: 'colors.first',
          color: colors.isNotEmpty ? colors.first : null,
        ),
      ]);
    }

    return _firstCandidate(<_PaletteCandidate>[
      (source: 'darkMutedColor', color: palette.darkMutedColor?.color),
      (source: 'darkVibrantColor', color: palette.darkVibrantColor?.color),
      (source: 'mutedColor', color: palette.mutedColor?.color),
      (source: 'dominantColor', color: palette.dominantColor?.color),
      (source: 'vibrantColor', color: palette.vibrantColor?.color),
      (source: 'colors.first', color: colors.isNotEmpty ? colors.first : null),
    ]);
  }

  static _PaletteCandidate _firstCandidate(List<_PaletteCandidate> candidates) {
    for (final candidate in candidates) {
      if (candidate.color != null) {
        return candidate;
      }
    }
    return (source: 'none', color: null);
  }

  static Color _logAndNormalize(
    Color source,
    Color fallbackColor, {
    required DetailBackgroundPaletteMode mode,
    required String sourceLabel,
    required String stage,
    String? debugContext,
  }) {
    final normalized = _normalize(source, fallbackColor);
    _debug(
      'candidate-picked stage=$stage mode=${mode.name} source=$sourceLabel '
      'raw=${_formatColor(source)} adjusted=${_formatColor(normalized.adjustedColor)} '
      'blended=${_formatColor(normalized.blendedColor)} '
      'initialContrast=${normalized.initialContrast.toStringAsFixed(2)} '
      'darkenSteps=${normalized.darkenSteps} '
      'finalContrast=${normalized.finalContrast.toStringAsFixed(2)} '
      'result=${_formatColor(normalized.result)} '
      'fallback=${_formatColor(fallbackColor)}${_contextText(debugContext)}',
    );
    return normalized.result;
  }

  static _NormalizationResult _normalize(Color source, Color fallbackColor) {
    final opaque = source.withValues(alpha: 1);
    final hsl = HSLColor.fromColor(opaque);
    final adjusted = hsl
        .withSaturation(math.min(hsl.saturation * 0.85, 0.55))
        .withLightness(_clampDouble(hsl.lightness, 0.10, 0.22));
    final adjustedColor = adjusted.toColor();

    var result =
        Color.lerp(adjustedColor, fallbackColor, 0.18) ?? fallbackColor;
    final blendedColor = result;
    final initialContrast = _contrastRatio(result, Colors.white);
    var darkenSteps = 0;

    while (_contrastRatio(result, Colors.white) < 4.8) {
      final darkened = HSLColor.fromColor(result).withLightness(
        math.max(HSLColor.fromColor(result).lightness - 0.04, 0.06),
      );
      if (darkened.toColor() == result) {
        break;
      }
      result = darkened.toColor();
      darkenSteps += 1;
    }

    return (
      adjustedColor: adjustedColor,
      blendedColor: blendedColor,
      darkenSteps: darkenSteps,
      finalContrast: _contrastRatio(result, Colors.white),
      initialContrast: initialContrast,
      result: result,
    );
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

  static void _debug(String message) {
    if (!kDebugMode) {
      return;
    }
    LogService.instance.debug(_logTag, message);
  }

  static String _contextText(String? debugContext) {
    if (debugContext == null || debugContext.isEmpty) {
      return '';
    }
    return ' | $debugContext';
  }

  static String _formatColor(Color? color) {
    if (color == null) {
      return 'null';
    }
    final hex =
        color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return '#$hex';
  }

  static String _formatRect(Rect? rect) {
    if (rect == null) {
      return 'full-image';
    }
    return 'Rect(${_formatDouble(rect.left)},${_formatDouble(rect.top)},'
        '${_formatDouble(rect.width)},${_formatDouble(rect.height)})';
  }

  static String _formatDouble(double value) => value.toStringAsFixed(2);

  static String _describePalette(PaletteGenerator palette) {
    final namedSwatches = <String>[
      'darkMuted=${_formatColor(palette.darkMutedColor?.color)}',
      'darkVibrant=${_formatColor(palette.darkVibrantColor?.color)}',
      'muted=${_formatColor(palette.mutedColor?.color)}',
      'dominant=${_formatColor(palette.dominantColor?.color)}',
      'vibrant=${_formatColor(palette.vibrantColor?.color)}',
    ];
    final topColors = palette.colors
        .take(3)
        .map(_formatColor)
        .toList(growable: false);
    return '${namedSwatches.join(', ')}; topColors=$topColors';
  }
}
