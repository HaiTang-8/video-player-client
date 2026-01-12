import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/episode.dart';
import '../../../data/models/subtitle_info.dart';

class CustomVideoControls extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onOpenPlaylist;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  final List<Episode>? episodes;
  final int currentEpisodeIndex;
  final void Function(int index)? onSelectEpisode;
  final List<SubtitleInfo> externalSubtitles;
  final String? serverUrl;
  final void Function(double speed)? onSpeedChanged;

  const CustomVideoControls({
    super.key,
    required this.player,
    required this.controller,
    this.title,
    this.onBack,
    this.onPrevious,
    this.onNext,
    this.hasPrevious = false,
    this.hasNext = false,
    this.onOpenPlaylist,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.episodes,
    this.currentEpisodeIndex = 0,
    this.onSelectEpisode,
    this.externalSubtitles = const [],
    this.serverUrl,
    this.onSpeedChanged,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  bool _visible = true;
  Timer? _hideTimer;
  bool _dragging = false;
  double _brightness = 0.5;
  bool _brightnessChanged = false;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  bool _showSeekOverlay = false;
  Duration _seekPosition = Duration.zero;
  Duration _seekStartPosition = Duration.zero;
  bool _wasPlayingBeforeSeek = false;

  // 统一手势状态
  Offset? _panStartPosition;
  String? _panDirection; // 'horizontal', 'vertical_left', 'vertical_right'
  double _panAccumulatedDx = 0;
  double _panAccumulatedDy = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = true; // 初始为 true，视频加载后自动播放
  bool _buffering = true; // 初始为 true，显示加载指示器
  double _volume = 1.0;
  List<AudioTrack> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];
  AudioTrack? _currentAudioTrack;
  SubtitleTrack? _currentSubtitleTrack;
  double _playbackSpeed = 1.0;

  // 长按倍速
  bool _isLongPressSpeed = false;
  double _originalSpeed = 1.0;
  Timer? _longPressTimer;

  /// 剧集列表的滚动位置缓存：
  /// - 关闭列表前记录当前 offset
  /// - 再次打开时使用该 offset 初始化，从而避免"每次打开都自动滚动到当前播放项"
  /// - 首次打开默认 0.0，即从顶部显示（仍然会高亮当前播放项）
  double _playlistScrollOffset = 0.0;

  /// 用于判断当前剧集列表是否发生了"换剧/换季/集数变化"等结构性变化：
  /// - 变化后重置 [_playlistScrollOffset]，避免把旧列表的滚动位置带到新列表导致定位错乱
  int? _playlistEpisodesKey;

  // 屏幕锁定状态（仅移动端）
  bool _isLocked = false;

  // 视频填充模式（true: 铺满无黑边, false: 默认保持比例）
  bool _isFillMode = false;

  final List<StreamSubscription> _subscriptions = [];
  final FocusNode _focusNode = FocusNode();
  double _volumeBeforeMute = 1.0;

  @override
  void initState() {
    super.initState();
    _playlistEpisodesKey = _buildEpisodesKey(widget.episodes);
    _initBrightness();
    _initCurrentTracks();
    _setupListeners();
    _startHideTimer();
  }

  @override
  void didUpdateWidget(covariant CustomVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = _buildEpisodesKey(widget.episodes);
    if (newKey != _playlistEpisodesKey) {
      _playlistEpisodesKey = newKey;
      _playlistScrollOffset = 0.0;
    }
  }

  int? _buildEpisodesKey(List<Episode>? episodes) {
    if (episodes == null || episodes.isEmpty) return null;
    final first = episodes.first;
    // 这里用「剧 + 季 + 集数」粗粒度区分列表内容，避免频繁误判。
    return Object.hash(first.tvShowId, first.seasonId, episodes.length);
  }

  Future<void> _initBrightness() async {
    if (WindowControls.isDesktop) return;
    try {
      _brightness = await ScreenBrightness().application;
    } catch (_) {}
  }

  void _initCurrentTracks() {
    final track = widget.player.state.track;
    _currentAudioTrack = track.audio;
    _currentSubtitleTrack = track.subtitle;
    _audioTracks = widget.player.state.tracks.audio;
    _subtitleTracks = widget.player.state.tracks.subtitle;
  }

  void _setupListeners() {
    _subscriptions.add(
      widget.player.stream.position.listen((p) {
        if (mounted && !_dragging) setState(() => _position = p);
      }),
    );
    _subscriptions.add(
      widget.player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    _subscriptions.add(
      widget.player.stream.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
    );
    _subscriptions.add(
      widget.player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
    );
    _subscriptions.add(
      widget.player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v / 100);
      }),
    );
    _subscriptions.add(
      widget.player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _audioTracks = tracks.audio;
            _subtitleTracks = tracks.subtitle;
          });
        }
      }),
    );
    _subscriptions.add(
      widget.player.stream.track.listen((track) {
        if (mounted) {
          setState(() {
            _currentAudioTrack = track.audio;
            _currentSubtitleTrack = track.subtitle;
          });
        }
      }),
    );
    _subscriptions.add(
      widget.player.stream.rate.listen((rate) {
        if (mounted) setState(() => _playbackSpeed = rate);
      }),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _longPressTimer?.cancel();
    _focusNode.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    if (_brightnessChanged && !WindowControls.isDesktop) {
      ScreenBrightness().resetApplicationScreenBrightness();
    }
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleVisibility() {
    setState(() {
      _visible = !_visible;
      if (_visible) _startHideTimer();
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (WindowControls.isDesktop) return;
    _panStartPosition = details.globalPosition;
    _panDirection = null;
    _panAccumulatedDx = 0;
    _panAccumulatedDy = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (WindowControls.isDesktop || _panStartPosition == null) return;

    _panAccumulatedDx += details.delta.dx.abs();
    _panAccumulatedDy += details.delta.dy.abs();

    // 判断方向（需要累计一定位移后才锁定）
    if (_panDirection == null && (_panAccumulatedDx > 10 || _panAccumulatedDy > 10)) {
      if (_panAccumulatedDx > _panAccumulatedDy) {
        _panDirection = 'horizontal';
        // 初始化进度拖动
        _wasPlayingBeforeSeek = _playing;
        if (_playing) widget.player.pause();
        setState(() {
          _seekStartPosition = _position;
          _seekPosition = _position;
          _showSeekOverlay = true;
        });
      } else {
        final screenWidth = MediaQuery.of(context).size.width;
        _panDirection = _panStartPosition!.dx < screenWidth / 2
            ? 'vertical_left'
            : 'vertical_right';
      }
    }

    if (_panDirection == null) return;

    if (_panDirection == 'horizontal') {
      final screenWidth = MediaQuery.of(context).size.width;
      final delta = details.delta.dx / screenWidth * _duration.inMilliseconds;
      setState(() {
        _seekPosition = Duration(
          milliseconds: (_seekPosition.inMilliseconds + delta.toInt()).clamp(
            0,
            _duration.inMilliseconds,
          ),
        );
      });
    } else {
      final delta = -details.delta.dy / 200;
      setState(() {
        if (_panDirection == 'vertical_left') {
          _brightness = (_brightness + delta).clamp(0.0, 1.0);
          _showBrightnessOverlay = true;
          _brightnessChanged = true;
          ScreenBrightness().setApplicationScreenBrightness(_brightness);
        } else {
          _volume = (_volume + delta).clamp(0.0, 1.0);
          _showVolumeOverlay = true;
          widget.player.setVolume(_volume * 100);
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (WindowControls.isDesktop) return;

    if (_panDirection == 'horizontal') {
      widget.player.seek(_seekPosition);
      if (_wasPlayingBeforeSeek) widget.player.play();
      setState(() => _showSeekOverlay = false);
    } else if (_panDirection == 'vertical_left') {
      setState(() => _showBrightnessOverlay = false);
    } else if (_panDirection == 'vertical_right') {
      setState(() => _showVolumeOverlay = false);
    }

    _panStartPosition = null;
    _panDirection = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!WindowControls.isDesktop) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // 右箭头：短按 seek，长按倍速
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent && event is! KeyRepeatEvent) {
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 300), () {
          _startLongPressSpeed();
        });
      } else if (event is KeyUpEvent) {
        if (_isLongPressSpeed) {
          _endLongPressSpeed();
        } else {
          _longPressTimer?.cancel();
          _seekRelative(5);
        }
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space) {
      widget.player.playOrPause();
      _showControlsTemporarily();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(0.1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-0.1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      if (widget.isFullscreen) {
        widget.onToggleFullscreen?.call();
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyN) {
      if (widget.hasNext) widget.onNext?.call();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyP) {
      if (widget.hasPrevious) widget.onPrevious?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showControlsTemporarily() {
    setState(() => _visible = true);
    _startHideTimer();
  }

  void _seekRelative(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    widget.player.seek(clamped);
    _showControlsTemporarily();
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 1.0);
    widget.player.setVolume(newVol * 100);
    _showControlsTemporarily();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      widget.player.setVolume(0);
    } else {
      widget.player.setVolume(_volumeBeforeMute * 100);
    }
    _showControlsTemporarily();
  }

  void _startLongPressSpeed() {
    if (_isLongPressSpeed) return;
    _originalSpeed = _playbackSpeed;
    widget.player.setRate(2.0);
    setState(() => _isLongPressSpeed = true);
  }

  void _endLongPressSpeed() {
    if (!_isLongPressSpeed) return;
    widget.player.setRate(_originalSpeed);
    setState(() => _isLongPressSpeed = false);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _onMouseMove(PointerEvent event) {
    if (!WindowControls.isDesktop) return;
    _showControlsTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: WindowControls.isDesktop,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onHover: _onMouseMove,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                if (WindowControls.isDesktop) {
                  widget.player.playOrPause();
                  _showControlsTemporarily();
                } else {
                  _toggleVisibility();
                }
              },
              onLongPressStart:
                  WindowControls.isDesktop || _isLocked ? null : (_) => _startLongPressSpeed(),
              onLongPressEnd:
                  WindowControls.isDesktop || _isLocked ? null : (_) => _endLongPressSpeed(),
              onPanStart: WindowControls.isDesktop || _isLocked ? null : _onPanStart,
              onPanUpdate: WindowControls.isDesktop || _isLocked ? null : _onPanUpdate,
              onPanEnd: WindowControls.isDesktop || _isLocked ? null : _onPanEnd,
              behavior: HitTestBehavior.translucent,
              child: Video(
                controller: widget.controller,
                controls: NoVideoControls,
                fit: _isFillMode ? BoxFit.cover : BoxFit.contain,
              ),
            ),
          // 亮度指示器
          if (_showBrightnessOverlay) _buildBrightnessOverlay(),
          // 音量指示器
          if (_showVolumeOverlay) _buildVolumeOverlay(),
          // 进度指示器
          if (_showSeekOverlay) _buildSeekOverlay(),
          // 控制栏
          if (_visible) ...[
            _buildTopBar(),
            if (!_isLocked) _buildBottomBar(),
            _buildProgressBar(),
          ],
          // 锁定按钮（仅移动端）
          if (_visible && !WindowControls.isDesktop) _buildLockButton(),
          // 缓冲指示器
          if (_buffering)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '缓冲中...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          // 长按倍速提示
          if (_isLongPressSpeed)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '倍速中 2x',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrightnessOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _brightness > 0.5 ? Icons.brightness_high : Icons.brightness_low,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: _brightness,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _volume > 0.5
                  ? Icons.volume_up
                  : (_volume > 0 ? Icons.volume_down : Icons.volume_off),
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: _volume,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSeekDelta(Duration delta) {
    final isNegative = delta.isNegative;
    final abs = delta.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final s = abs.inSeconds.remainder(60);
    final prefix = isNegative ? '-' : '+';
    if (h > 0) return '$prefix${h}小时${m}分钟${s}秒';
    if (m > 0) return '$prefix${m}分钟${s}秒';
    return '$prefix${s}秒';
  }

  Widget _buildSeekOverlay() {
    final delta = _seekPosition - _seekStartPosition;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatSeekDelta(delta),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDuration(_seekPosition)} / ${_formatDuration(_duration)}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final onBack =
        widget.onBack ??
        () {
          Navigator.of(context).maybePop();
        };
    final padding = MediaQuery.of(context).padding;
    final horizontalPadding = WindowControls.isMacOS ? 72.0 : 12.0;
    const barHeight = 44.0;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            top: padding.top + 10,
            left: padding.left + horizontalPadding,
            right: padding.right + (WindowControls.isWindows ? 0 : horizontalPadding),
            bottom: 10,
          ),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              height: WindowControls.isMacOS ? 52 : barHeight,
              child: Stack(
                children: [
                  if (WindowControls.isDesktop)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => WindowControls.startDrag(),
                        onDoubleTap: () => WindowControls.toggleMaximize(),
                      ),
                    ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!_isLocked) ...[
                          AppBackButton(onPressed: onBack, color: Colors.white, leftPadding: 0),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            widget.title ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (WindowControls.isWindows) ...[
                          const SizedBox(width: 16),
                          _WindowCaptionButton(
                            icon: Icons.remove,
                            onPressed: () => WindowControls.minimize(),
                          ),
                          _WindowCaptionButton(
                            icon: Icons.crop_square,
                            onPressed: () => WindowControls.toggleMaximize(),
                          ),
                          _WindowCaptionButton(
                            icon: Icons.close,
                            hoverColor: const Color(0xFFE81123),
                            onPressed: () => WindowControls.close(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final padding = MediaQuery.of(context).padding;
    final bottomPadding = WindowControls.isDesktop ? 0.0 : padding.bottom;
    final horizontalPadding = WindowControls.isMacOS ? 72.0 : 12.0;
    return Positioned(
      left: horizontalPadding + padding.left,
      right: horizontalPadding + padding.right,
      bottom: _isLocked ? (padding.bottom + 16) : (56 + bottomPadding),
      child: Row(
        children: [
          Text(
            _formatDuration(_position),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: IgnorePointer(
              ignoring: _isLocked,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: _isLocked ? 0 : 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value:
                      _duration.inMilliseconds > 0
                          ? _position.inMilliseconds / _duration.inMilliseconds
                          : 0,
                  onChangeStart: (_) {
                    _dragging = true;
                    _hideTimer?.cancel();
                  },
                  onChanged: (v) {
                    setState(() {
                      _position = Duration(
                        milliseconds: (v * _duration.inMilliseconds).round(),
                      );
                    });
                  },
                  onChangeEnd: (v) {
                    _dragging = false;
                    widget.player.seek(
                      Duration(
                        milliseconds: (v * _duration.inMilliseconds).round(),
                      ),
                    );
                    _startHideTimer();
                  },
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_duration),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final padding = MediaQuery.of(context).padding;
    final horizontalPadding = WindowControls.isMacOS ? 72.0 : 12.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: padding.bottom + 8,
          left: padding.left + horizontalPadding,
          right: padding.right + horizontalPadding,
          top: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 中间播放控制按钮（绝对居中）
            _buildPlayControls(),
            // 左右两侧控件
            Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (WindowControls.isDesktop) _buildVolumeControl(),
                    _buildSpeedButton(),
                    _buildFillModeButton(),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIconButton(Icons.graphic_eq, () => _showAudioTrackSheet()),
                    _buildIconButton(Icons.subtitles_outlined, () => _showSubtitleSheet(),
                        isLast: !WindowControls.isDesktop && (widget.episodes == null || widget.episodes!.isEmpty)),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      _buildIconButton(Icons.format_list_bulleted, _showPlaylistMenu,
                          isLast: !WindowControls.isDesktop),
                    if (WindowControls.isDesktop)
                      _buildIconButton(
                        widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        widget.onToggleFullscreen,
                        isLast: true,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _volume == 0 ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 28,
          ),
          onPressed: () {
            widget.player.setVolume(_volume == 0 ? 100 : 0);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _volume,
              onChanged: (v) => widget.player.setVolume(v * 100),
              activeColor: Colors.white,
              inactiveColor: Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFillModeButton() {
    final isDesktop = WindowControls.isDesktop;
    return IconButton(
      onPressed: () {
        setState(() => _isFillMode = !_isFillMode);
        _showControlsTemporarily();
      },
      icon: Icon(
        _isFillMode ? Icons.zoom_in_map : Icons.zoom_out_map,
        color: Colors.white,
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: isDesktop ? 48 : 40),
    );
  }

  Widget _buildSpeedButton() {
    final isDesktop = WindowControls.isDesktop;
    return GestureDetector(
      onTap: _showSpeedSheet,
      child: Container(
        constraints: BoxConstraints(minWidth: isDesktop ? 48 : 40),
        alignment: Alignment.center,
        child: Text(
          '${_playbackSpeed}x',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPlayControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.skip_previous,
            color: widget.hasPrevious ? Colors.white : Colors.white38,
            size: 36,
          ),
          onPressed: widget.hasPrevious ? widget.onPrevious : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
            size: 36,
          ),
          onPressed: () => widget.player.playOrPause(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            Icons.skip_next,
            color: widget.hasNext ? Colors.white : Colors.white38,
            size: 36,
          ),
          onPressed: widget.hasNext ? widget.onNext : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
      ],
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback? onPressed, {
    GlobalKey? key,
    bool isLast = false,
  }) {
    final isDesktop = WindowControls.isDesktop;
    final minW = isDesktop ? 48.0 : 40.0;
    if (isLast) {
      return Padding(
        padding: EdgeInsets.only(left: (minW - 28) / 2),
        child: GestureDetector(
          key: key,
          onTap: onPressed,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      );
    }
    return IconButton(
      key: key,
      icon: Icon(icon, color: Colors.white, size: 28),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: minW),
    );
  }

  Widget _buildCheckMark() {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, color: Colors.black, size: 10),
    );
  }

  Widget _buildLockButton() {
    final padding = MediaQuery.of(context).padding;
    return Positioned(
      right: padding.right + 12,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            setState(() => _isLocked = !_isLocked);
            _showControlsTemporarily();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isLocked ? Icons.lock : Icons.lock_open,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '倍速',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                ...speeds.map(
                  (s) => ListTile(
                    title: Text(
                      '${s}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing:
                        (_playbackSpeed - s).abs() < 0.01
                            ? const Icon(Icons.check, color: Colors.red)
                            : null,
                    onTap: () {
                      widget.player.setRate(s);
                      widget.onSpeedChanged?.call(s);
                      Navigator.pop(ctx);
                      _startHideTimer();
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showSubtitleSheet() => _showSubtitleMenu();

  void _showAudioTrackSheet() => _showAudioTrackMenu();

  void _showSubtitleMenu() async {
    final panelWidth =
        WindowControls.isDesktop
            ? 200.0
            : MediaQuery.of(context).size.width * 0.6;
    final result = await showGeneralDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, _, __) {
        final currentId = _currentSubtitleTrack?.id;
        final embeddedTracks =
            _subtitleTracks.where((t) => t.id != 'no').toList();
        final externalSubs = widget.externalSubtitles;

        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: Material(
              color: const Color(0xFF1C1C1E),
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          '字幕',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8),
                          children: [
                            ListTile(
                              dense: true,
                              title: const Text(
                                '关闭',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              trailing:
                                  currentId == 'no' || currentId == null
                                      ? _buildCheckMark()
                                      : null,
                              onTap:
                                  () => Navigator.pop(ctx, SubtitleTrack.no()),
                            ),
                            if (embeddedTracks.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text(
                                  '内嵌字幕',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...embeddedTracks.map(
                                (t) => ListTile(
                                  dense: true,
                                  title: Text(
                                    t.title ?? t.language ?? t.id,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  trailing:
                                      currentId == t.id
                                          ? _buildCheckMark()
                                          : null,
                                  onTap: () => Navigator.pop(ctx, t),
                                ),
                              ),
                            ],
                            if (externalSubs.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text(
                                  '外挂字幕',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...externalSubs.map(
                                (sub) => ListTile(
                                  dense: true,
                                  title: Text(
                                    sub.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  trailing:
                                      currentId == 'external_${sub.path}'
                                          ? _buildCheckMark()
                                          : null,
                                  onTap:
                                      () =>
                                          Navigator.pop(ctx, {'external': sub}),
                                ),
                              ),
                            ],
                            if (embeddedTracks.isEmpty && externalSubs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  '无可用字幕',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result != null) {
      if (result is SubtitleTrack) {
        widget.player.setSubtitleTrack(result);
      } else if (result is Map && result['external'] != null) {
        final sub = result['external'] as SubtitleInfo;
        final subUrl =
            sub.url.startsWith('http')
                ? sub.url
                : '${widget.serverUrl ?? ''}${sub.url}';
        widget.player.setSubtitleTrack(
          SubtitleTrack.uri(subUrl, title: sub.displayName),
        );
      }
    }
    _startHideTimer();
  }

  void _showAudioTrackMenu() async {
    final panelWidth =
        WindowControls.isDesktop
            ? 200.0
            : MediaQuery.of(context).size.width * 0.6;
    final result = await showGeneralDialog<AudioTrack>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, _, __) {
        final currentId = _currentAudioTrack?.id;
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: Material(
              color: const Color(0xFF1C1C1E),
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          '音轨',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8),
                          children: [
                            ..._audioTracks
                                .where((t) => t.id != 'no')
                                .map(
                                  (t) => ListTile(
                                    dense: true,
                                    title: Text(
                                      t.title ?? t.language ?? t.id,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    trailing:
                                        currentId == t.id
                                            ? _buildCheckMark()
                                            : null,
                                    onTap: () => Navigator.pop(ctx, t),
                                  ),
                                ),
                            if (_audioTracks.where((t) => t.id != 'no').isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  '无可用音轨',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result != null) widget.player.setAudioTrack(result);
    _startHideTimer();
  }

  void _showPlaylistMenu() async {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return;

    final seasonNumber = episodes.first.seasonNumber;
    final totalEpisodes = episodes.length;
    final currentIndex = widget.currentEpisodeIndex;

    const itemSpacing = 8.0;
    final scrollController = ScrollController(
      initialScrollOffset: _playlistScrollOffset,
    );

    void saveScrollOffset() {
      if (scrollController.hasClients) {
        _playlistScrollOffset = scrollController.offset;
      }
    }

    scrollController.addListener(saveScrollOffset);

    final panelWidth =
        WindowControls.isDesktop
            ? 280.0
            : MediaQuery.of(context).size.width * 0.7;
    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, secondaryAnim) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: const Color(0xFF1C1C1E),
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: Text(
                          '第$seasonNumber季 (共$totalEpisodes集)',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: episodes.length,
                          itemBuilder: (_, index) {
                            final ep = episodes[index];
                            final isCurrent = index == currentIndex;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: itemSpacing,
                              ),
                              child: GestureDetector(
                                onTap: () => Navigator.pop(ctx, index),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isCurrent
                                            ? const Color(0xFF3A3A3C)
                                            : const Color(0xFF2C2C2E),
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        isCurrent
                                            ? Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            )
                                            : null,
                                  ),
                                  child: Row(
                                    children: [
                                      if (isCurrent) ...[
                                        const Icon(
                                          Icons.play_circle_outline,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Text(
                                          '${ep.episodeNumber}. ${ep.name ?? '第 ${ep.episodeNumber} 集'}',
                                          style: TextStyle(
                                            color:
                                                isCurrent
                                                    ? Colors.white
                                                    : Colors.white70,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    saveScrollOffset();
    scrollController.dispose();
    if (result != null && result != widget.currentEpisodeIndex) {
      widget.onSelectEpisode?.call(result);
    }
    _startHideTimer();
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;

  const _WindowCaptionButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered ? (widget.hoverColor ?? Colors.white24) : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 44,
          color: bg,
          child: Center(child: Icon(widget.icon, size: 16, color: Colors.white)),
        ),
      ),
    );
  }
}
