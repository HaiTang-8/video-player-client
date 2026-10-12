import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/detail_background_palette.dart';
import '../utils/image_proxy.dart';

/// 详情页顶部 Hero 图的选图与尺寸结果。
class DetailHeroImage {
  static const double _mobilePosterBottomInset = 96;
  static const double _posterAspect = 2 / 3;
  static const double _backdropAspect = 16 / 9;
  static const double _minPosterVisibleFraction = 0.85;
  static const Set<String> _smallTMDBSizes = {
    'w92',
    'w154',
    'w185',
    'w342',
    'w500',
  };

  final String? imageUrl;
  final double imageHeight;
  final double layoutHeight;
  final bool usePoster;
  final BoxFit fit;
  final double paletteFraction;

  const DetailHeroImage._({
    required this.imageUrl,
    required this.imageHeight,
    required this.layoutHeight,
    required this.usePoster,
    required this.fit,
    required this.paletteFraction,
  });

  DetailBackgroundPaletteMode get paletteMode =>
      usePoster
          ? DetailBackgroundPaletteMode.posterBottom
          : DetailBackgroundPaletteMode.fullImage;

  /// 移动端优先竖版海报；当屏幕比例导致海报可见部分不足
  /// [_minPosterVisibleFraction] 时（平板/横屏/折叠屏），改用横版背景图。
  /// 桌面端优先横版背景图。
  factory DetailHeroImage.resolve({
    required String? posterPath,
    required String? backdropPath,
    required Size screenSize,
    required String? serverBaseUrl,
    required bool isDesktop,
    double mobilePosterMaxHeightFactor = 0.85,
  }) {
    final hasPoster = posterPath != null && posterPath.isNotEmpty;
    final hasBackdrop = backdropPath != null && backdropPath.isNotEmpty;
    final posterIdealHeight = screenSize.width / _posterAspect;
    final posterMaxHeight = screenSize.height * mobilePosterMaxHeightFactor;
    final posterFits =
        posterIdealHeight * _minPosterVisibleFraction <= posterMaxHeight;

    final usePoster =
        isDesktop ? !hasBackdrop : hasPoster && (posterFits || !hasBackdrop);

    double imageHeight;
    var paletteFraction = 1.0;
    if (usePoster && isDesktop) {
      imageHeight = screenSize.height * 0.75;
    } else if (usePoster) {
      imageHeight = posterIdealHeight.clamp(0.0, posterMaxHeight).toDouble();
      final visible = imageHeight / posterIdealHeight;
      if (visible < 1) {
        paletteFraction = (visible * 20).floorToDouble() / 20;
      }
    } else {
      imageHeight =
          (screenSize.width / _backdropAspect)
              .clamp(screenSize.height * 0.55, screenSize.height * 0.9)
              .toDouble();
    }
    imageHeight = imageHeight.ceilToDouble();

    final layoutHeight =
        (!isDesktop && usePoster
                ? imageHeight + _mobilePosterBottomInset
                : imageHeight)
            .ceilToDouble();

    final rawPath = usePoster ? posterPath : backdropPath;
    final imageUrl =
        rawPath != null && rawPath.isNotEmpty
            ? ImageProxy.proxyTMDBIfNeeded(
              _upsizeTMDB(rawPath, usePoster ? 'w780' : 'w1280'),
              serverBaseUrl,
            )
            : null;

    return DetailHeroImage._(
      imageUrl: imageUrl,
      imageHeight: imageHeight,
      layoutHeight: layoutHeight,
      usePoster: usePoster,
      fit: usePoster && !isDesktop ? BoxFit.fitWidth : BoxFit.cover,
      paletteFraction: paletteFraction,
    );
  }

  static String _upsizeTMDB(String path, String targetSize) {
    if (!ImageProxy.isTMDBImageUrl(path)) {
      return path;
    }
    final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
    final currentSize = segments.length >= 3 ? segments[2] : '';
    return _smallTMDBSizes.contains(currentSize)
        ? ImageProxy.withTMDBSize(path, targetSize)
        : path;
  }
}

/// 详情页顶部沉浸式背景：Hero 图 + 渐变蒙版 + 叠加内容。
class DetailHeroBackground extends StatelessWidget {
  static const double _mobileContentMaxWidth = 600;

  final DetailHeroImage heroImage;
  final String? accessToken;
  final Color backgroundColor;
  final Color surfaceColor;
  final bool isDesktop;
  final Widget content;

  const DetailHeroBackground({
    super.key,
    required this.heroImage,
    required this.accessToken,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.isDesktop,
    required this.content,
  });

  static Color surfaceColorFor(BuildContext context, Color backgroundColor) {
    final fallbackColor = context.appColors.cardBackground;
    return Color.lerp(backgroundColor, fallbackColor, 0.24) ?? fallbackColor;
  }

  static Color _highlightColor(Color backgroundColor) {
    final hsl = HSLColor.fromColor(backgroundColor);
    return hsl
        .withSaturation((hsl.saturation * 1.12).clamp(0.0, 0.62))
        .withLightness((hsl.lightness + 0.05).clamp(0.12, 0.30))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final imageHeight = heroImage.imageHeight;
    final layoutHeight = heroImage.layoutHeight;
    final gradientHeight =
        ((imageHeight * 0.5) + (layoutHeight - imageHeight)).ceilToDouble();
    final bottomMaskHeight =
        (gradientHeight * 1.45).clamp(0.0, layoutHeight).toDouble();
    final imageUrl = heroImage.imageUrl;
    final highlightColor = _highlightColor(backgroundColor);
    final bridgeColor =
        Color.lerp(highlightColor, surfaceColor, 0.42) ?? surfaceColor;

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: layoutHeight,
          color: isDesktop ? backgroundColor : surfaceColor,
        ),
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
            httpHeaders:
                accessToken != null
                    ? {'Authorization': 'Bearer $accessToken'}
                    : null,
            width: double.infinity,
            height: imageHeight,
            fit: heroImage.fit,
            alignment: Alignment.topCenter,
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        if (!isDesktop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: gradientHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors:
                    isDesktop
                        ? [
                          backgroundColor.withValues(alpha: 0.0),
                          backgroundColor.withValues(alpha: 0.2),
                          backgroundColor.withValues(alpha: 0.5),
                          backgroundColor.withValues(alpha: 0.8),
                          backgroundColor,
                        ]
                        : [
                          highlightColor.withValues(alpha: 0.0),
                          highlightColor.withValues(alpha: 0.18),
                          bridgeColor.withValues(alpha: 0.48),
                          surfaceColor.withValues(alpha: 0.82),
                          surfaceColor,
                        ],
                stops: const [0.0, 0.18, 0.45, 0.78, 1.0],
              ),
            ),
          ),
        ),
        if (!isDesktop)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomMaskHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surfaceColor.withValues(alpha: 0.0),
                    surfaceColor.withValues(alpha: 0.18),
                    surfaceColor.withValues(alpha: 0.42),
                    surfaceColor.withValues(alpha: 0.74),
                    surfaceColor.withValues(alpha: 0.94),
                    surfaceColor,
                  ],
                  stops: const [0.0, 0.2, 0.42, 0.66, 0.86, 1.0],
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 24,
          child:
              isDesktop
                  ? content
                  : Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _mobileContentMaxWidth,
                      ),
                      child: content,
                    ),
                  ),
        ),
      ],
    );
  }
}

/// 详情页背景取色状态：按 Hero 图异步提取主色并缓存在 State 中。
mixin DetailHeroPaletteMixin<T extends StatefulWidget> on State<T> {
  Color? _heroPaletteColor;
  String? _heroPaletteImageUrl;
  DetailBackgroundPaletteMode _heroPaletteMode =
      DetailBackgroundPaletteMode.fullImage;
  double _heroPaletteFraction = 1;

  String get heroPaletteDebugLabel;

  bool _isCurrentHeroPalette(
    String imageUrl,
    DetailBackgroundPaletteMode mode,
    double fraction,
  ) =>
      _heroPaletteImageUrl == imageUrl &&
      _heroPaletteMode == mode &&
      _heroPaletteFraction == fraction;

  void resolveHeroPalette(
    DetailHeroImage heroImage,
    String? accessToken, {
    required bool isDesktop,
  }) {
    final imageUrl = heroImage.imageUrl;
    if (isDesktop || imageUrl == null || imageUrl.isEmpty) {
      return;
    }
    final mode = heroImage.paletteMode;
    final fraction = heroImage.paletteFraction;
    if (_isCurrentHeroPalette(imageUrl, mode, fraction)) {
      return;
    }

    _heroPaletteImageUrl = imageUrl;
    _heroPaletteMode = mode;
    _heroPaletteFraction = fraction;
    _heroPaletteColor = DetailBackgroundPalette.getCached(
      imageUrl,
      mode: mode,
      visibleFraction: fraction,
    );
    final headers =
        accessToken != null
            ? <String, String>{'Authorization': 'Bearer $accessToken'}
            : null;

    DetailBackgroundPalette.resolve(
      imageUrl,
      provider: CachedNetworkImageProvider(imageUrl, headers: headers),
      fallbackColor: AppColors.dark.cardBackground,
      mode: mode,
      visibleFraction: fraction,
      debugContext:
          '$heroPaletteDebugLabel mode=${mode.name} '
          'fraction=$fraction imageUrl=$imageUrl',
    ).then((color) {
      if (!mounted ||
          !_isCurrentHeroPalette(imageUrl, mode, fraction) ||
          _heroPaletteColor == color) {
        return;
      }
      setState(() {
        _heroPaletteColor = color;
      });
    });
  }

  /// 传入 [heroImage] 时按该图取色，否则使用当前已解析的图。
  Color heroBackgroundColor(
    BuildContext context,
    DetailHeroImage? heroImage, {
    required bool isDesktop,
  }) =>
      isDesktop
          ? context.appColors.cardBackground
          : _heroColor(context, heroImage);

  /// 桌面端不会记录取色状态，此处无需判断平台。
  Color _heroColor(BuildContext context, DetailHeroImage? heroImage) {
    final fallbackColor = context.appColors.cardBackground;
    final imageUrl = heroImage?.imageUrl ?? _heroPaletteImageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return fallbackColor;
    }
    final mode = heroImage?.paletteMode ?? _heroPaletteMode;
    final fraction = heroImage?.paletteFraction ?? _heroPaletteFraction;
    final cachedColor = DetailBackgroundPalette.getCached(
      imageUrl,
      mode: mode,
      visibleFraction: fraction,
    );
    if (_isCurrentHeroPalette(imageUrl, mode, fraction)) {
      return _heroPaletteColor ?? cachedColor ?? fallbackColor;
    }
    return cachedColor ?? fallbackColor;
  }

  Color heroSurfaceColor(BuildContext context) =>
      DetailHeroBackground.surfaceColorFor(context, _heroColor(context, null));
}
