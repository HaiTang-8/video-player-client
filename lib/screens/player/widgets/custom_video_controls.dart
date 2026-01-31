import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn show showDropdown, DropdownMenu, MenuButton, MenuDivider, MenuItem;
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons, BootstrapIcons;
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

  // D键二倍速锁定
  bool _isDoubleSpeedLocked = false;
  double _speedBeforeDoubleLock = 1.0;

  // 屏幕锁定状态（仅移动端）
  bool _isLocked = false;

  // 视频填充模式（true: 铺满无黑边, false: 默认保持比例）
  bool _isFillMode = false;

  // 媒体信息面板
  bool _showMediaInfo = false;
  Map<String, String> _mediaInfo = {};
  Timer? _mediaInfoTimer;

  final List<StreamSubscription> _subscriptions = [];
  final FocusNode _focusNode = FocusNode();
  double _volumeBeforeMute = 1.0;

  @override
  void initState() {
    super.initState();
    _initBrightness();
    _initCurrentTracks();
    _setupListeners();
    _startHideTimer();
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
    _mediaInfoTimer?.cancel();
    // 确保长按倍速状态被重置
    if (_isLongPressSpeed) {
      widget.player.setRate(_originalSpeed);
    }
    _focusNode.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    if (_brightnessChanged && !WindowControls.isDesktop) {
      try {
        ScreenBrightness().resetApplicationScreenBrightness();
      } catch (_) {}
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
      final delta = details.delta.dx / screenWidth * _duration.inMilliseconds * 0.3;
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
          try {
            ScreenBrightness().setApplicationScreenBrightness(_brightness);
          } catch (_) {}
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
    } else if (key == LogicalKeyboardKey.tab) {
      _toggleMediaInfo();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyD) {
      _toggleDoubleSpeedLock();
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

  void _toggleDoubleSpeedLock() {
    if (_isDoubleSpeedLocked) {
      widget.player.setRate(_speedBeforeDoubleLock);
      setState(() => _isDoubleSpeedLocked = false);
    } else {
      _speedBeforeDoubleLock = _playbackSpeed;
      widget.player.setRate(2.0);
      setState(() => _isDoubleSpeedLocked = true);
    }
  }

  Future<void> _fetchMediaInfo() async {
    final platform = widget.player.platform;
    if (platform is! NativePlayer) return;

    try {
      final info = <String, String>{};

      // 视频参数
      final videoCodec = await platform.getProperty('video-codec');
      final videoWidth = await platform.getProperty('video-params/w');
      final videoHeight = await platform.getProperty('video-params/h');
      final fps = await platform.getProperty('container-fps');
      final videoBitrate = await platform.getProperty('video-bitrate');
      final hwdec = await platform.getProperty('hwdec-current');

      if (videoCodec.isNotEmpty) info['视频编码'] = videoCodec;
      if (videoWidth.isNotEmpty && videoHeight.isNotEmpty) {
        info['分辨率'] = '${videoWidth}x$videoHeight';
      }
      if (fps.isNotEmpty) {
        final fpsVal = double.tryParse(fps);
        info['帧率'] = fpsVal != null ? '${fpsVal.toStringAsFixed(2)} fps' : fps;
      }
      if (videoBitrate.isNotEmpty) {
        final br = int.tryParse(videoBitrate);
        if (br != null && br > 0) {
          info['视频码率'] = '${(br / 1000).toStringAsFixed(0)} kbps';
        }
      }
      if (hwdec.isNotEmpty && hwdec != 'no') info['硬解'] = hwdec;

      // 音频参数
      final audioCodec = await platform.getProperty('audio-codec-name');
      final channels = await platform.getProperty('audio-params/channel-count');
      final sampleRate = await platform.getProperty('audio-params/samplerate');
      final audioBitrate = await platform.getProperty('audio-bitrate');

      if (audioCodec.isNotEmpty) info['音频编码'] = audioCodec;
      if (channels.isNotEmpty) {
        final ch = int.tryParse(channels);
        info['声道'] = ch == 2 ? '立体声' : (ch == 1 ? '单声道' : '$ch 声道');
      }
      if (sampleRate.isNotEmpty) {
        final sr = int.tryParse(sampleRate);
        info['采样率'] = sr != null ? '${(sr / 1000).toStringAsFixed(1)} kHz' : sampleRate;
      }
      if (audioBitrate.isNotEmpty) {
        final br = int.tryParse(audioBitrate);
        if (br != null && br > 0) {
          info['音频码率'] = '${(br / 1000).toStringAsFixed(0)} kbps';
        }
      }

      // 播放信息
      info['倍速'] = '${_playbackSpeed}x';
      info['音量'] = '${(_volume * 100).toInt()}%';

      if (mounted) setState(() => _mediaInfo = info);
    } catch (_) {}
  }

  void _toggleMediaInfo() {
    setState(() => _showMediaInfo = !_showMediaInfo);
    if (_showMediaInfo) {
      _fetchMediaInfo();
      _mediaInfoTimer?.cancel();
      _mediaInfoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_showMediaInfo && mounted) _fetchMediaInfo();
      });
    } else {
      _mediaInfoTimer?.cancel();
    }
  }

  Widget _buildMediaInfoPanel() {
    final padding = MediaQuery.of(context).padding;
    return Positioned(
      top: padding.top + 16,
      left: padding.left + 16,
      child: GestureDetector(
        onTap: () => setState(() => _showMediaInfo = false),
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.info, color: Colors.white70),
                  const SizedBox(width: 6),
                  const Text(
                    '媒体信息',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showMediaInfo = false),
                    child: const Icon(LucideIcons.x, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 8),
              if (_mediaInfo.isEmpty)
                const Text(
                  '加载中...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                )
              else
                ..._mediaInfo.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            e.value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
              onDoubleTap: WindowControls.isDesktop ? widget.onToggleFullscreen : null,
              onLongPressStart:
                  WindowControls.isDesktop || _isLocked
                      ? null
                      : (details) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          if (details.globalPosition.dx < screenWidth / 2) {
                            _toggleMediaInfo();
                          } else {
                            _startLongPressSpeed();
                          }
                        },
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
          // 媒体信息面板
          if (_showMediaInfo) _buildMediaInfoPanel(),
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
              top: MediaQuery.of(context).padding.top + 20,
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
              _brightness > 0.5 ? LucideIcons.sun : LucideIcons.moon,
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
                  ? LucideIcons.volume2
                  : (_volume > 0 ? LucideIcons.volume1 : LucideIcons.volumeX),
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
    const horizontalPadding = 12.0;
    final leftPadding = WindowControls.isMacOS ? 68.0 : horizontalPadding;
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
            top: WindowControls.isDesktop ? 0 : (padding.top + 10),
            left: padding.left + leftPadding,
            right: padding.right + (WindowControls.isWindows ? 0 : horizontalPadding),
            bottom: WindowControls.isDesktop ? 0 : 10,
          ),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              height: barHeight,
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
                            icon: LucideIcons.minus,
                            onPressed: () => WindowControls.minimize(),
                          ),
                          _WindowCaptionButton(
                            icon: LucideIcons.square,
                            onPressed: () => WindowControls.toggleMaximize(),
                          ),
                          _WindowCaptionButton(
                            icon: LucideIcons.x,
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
    const horizontalPadding = 12.0;
    return Positioned(
      left: horizontalPadding + padding.left,
      right: horizontalPadding + padding.right,
      bottom: _isLocked ? (padding.bottom + 16) : (56 + bottomPadding),
      child: Row(
        children: [
          Text(
            _formatDuration(_position),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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
                          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
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
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final padding = MediaQuery.of(context).padding;
    const horizontalPadding = 12.0;
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
                    _buildAudioTrackButton(),
                    const SizedBox(width: 12),
                    _buildSubtitleButton(
                        isLast: !WindowControls.isDesktop && (widget.episodes == null || widget.episodes!.isEmpty)),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      _buildIconButton(LucideIcons.list, _showPlaylistMenu,
                          isLast: !WindowControls.isDesktop, size: 30),
                    if (WindowControls.isDesktop)
                      _buildIconButton(
                        widget.isFullscreen ? LucideIcons.minimize : LucideIcons.maximize,
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
        GestureDetector(
          onTap: () {
            widget.player.setVolume(_volume == 0 ? 100 : 0);
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2,
              color: Colors.white,
              size: 22,
            ),
          ),
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
        _isFillMode ? LucideIcons.minimize2 : LucideIcons.maximize2,
        color: Colors.white,
        size: 22,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: isDesktop ? 48 : 40),
    );
  }

  Widget _buildSpeedButton() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    final isDesktop = WindowControls.isDesktop;
    return Builder(
      builder: (menuContext) => GestureDetector(
        onTap: () {
          _hideTimer?.cancel();
          _showSpeedMenu(menuContext, speeds);
        },
        child: Container(
          constraints: BoxConstraints(minWidth: isDesktop ? 48 : 40),
          alignment: Alignment.center,
          child: Text(
            '${_playbackSpeed}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedMenu(BuildContext context, List<double> speeds) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final padding = MediaQuery.of(context).padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7;

    shadcn.showDropdown(
      context: context,
      margin: isMobile
          ? EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              top: padding.top,
              bottom: padding.bottom,
            )
          : null,
      builder: (dropdownContext) {
        final children = <shadcn.MenuItem>[];
        for (var i = 0; i < speeds.length; i++) {
          final s = speeds[i];
          final selected = (_playbackSpeed - s).abs() < 0.01;
          children.add(
            shadcn.MenuButton(
              trailing: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
              child: Text('${s}x'),
              onPressed: (_) {
                widget.player.setRate(s);
                widget.onSpeedChanged?.call(s);
                _startHideTimer();
              },
            ),
          );
          if (i < speeds.length - 1) {
            children.add(const shadcn.MenuDivider());
          }
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(dropdownContext).copyWith(scrollbars: false),
            child: shadcn.DropdownMenu(children: children),
          ),
        );
      },
    );
  }

  Widget _buildAudioTrackButton({bool isLast = false}) {
    return Builder(
      builder: (menuContext) => GestureDetector(
        onTap: () {
          _hideTimer?.cancel();
          _showAudioTrackMenu(menuContext);
        },
        child: Padding(
          padding: EdgeInsets.only(left: isLast ? 6 : 0),
          child: const SizedBox(
            width: 30,
            height: 30,
            child: Center(child: Icon(LucideIcons.audioLines, color: Colors.white, size: 26)),
          ),
        ),
      ),
    );
  }

  void _showAudioTrackMenu(BuildContext context) {
    final tracks = _audioTracks.where((t) => t.id != 'no').toList();
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final padding = MediaQuery.of(context).padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7;

    shadcn.showDropdown(
      context: context,
      margin: isMobile
          ? EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              top: padding.top,
              bottom: padding.bottom,
            )
          : null,
      builder: (dropdownContext) {
        if (tracks.isEmpty) {
          return shadcn.DropdownMenu(
            children: [
              shadcn.MenuButton(
                child: const Text('无可用音轨'),
                onPressed: null,
              ),
            ],
          );
        }
        final children = <shadcn.MenuItem>[];
        for (var i = 0; i < tracks.length; i++) {
          final t = tracks[i];
          final selected = _currentAudioTrack?.id == t.id;
          children.add(shadcn.MenuButton(
            trailing: selected
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : null,
            child: Text(t.title ?? t.language ?? t.id),
            onPressed: (_) {
              widget.player.setAudioTrack(t);
              _startHideTimer();
            },
          ));
          if (i < tracks.length - 1) {
            children.add(const shadcn.MenuDivider());
          }
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(dropdownContext).copyWith(scrollbars: false),
            child: shadcn.DropdownMenu(children: children),
          ),
        );
      },
    );
  }

  Widget _buildSubtitleButton({bool isLast = false}) {
    return Builder(
      builder: (menuContext) => GestureDetector(
        onTap: () {
          _hideTimer?.cancel();
          _showSubtitleMenu(menuContext);
        },
        child: Padding(
          padding: EdgeInsets.only(left: isLast ? 6 : 0),
          child: const SizedBox(
            width: 30,
            height: 30,
            child: Center(child: Icon(LucideIcons.captions, color: Colors.white, size: 30)),
          ),
        ),
      ),
    );
  }

  void _showSubtitleMenu(BuildContext context) {
    final embeddedTracks = _subtitleTracks.where((t) => t.id != 'no').toList();
    final externalSubs = widget.externalSubtitles;
    final currentId = _currentSubtitleTrack?.id;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final padding = MediaQuery.of(context).padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7;

    shadcn.showDropdown(
      context: context,
      margin: isMobile
          ? EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              top: padding.top,
              bottom: padding.bottom,
            )
          : null,
      builder: (dropdownContext) {
        final closeSelected = currentId == 'no' || currentId == null;
        final children = <shadcn.MenuItem>[
          shadcn.MenuButton(
            trailing: closeSelected
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : null,
            child: const Text('关闭'),
            onPressed: (_) {
              widget.player.setSubtitleTrack(SubtitleTrack.no());
              _startHideTimer();
            },
          ),
        ];

        if (embeddedTracks.isNotEmpty) {
          children.add(const shadcn.MenuDivider());
          for (var i = 0; i < embeddedTracks.length; i++) {
            final t = embeddedTracks[i];
            final selected = currentId == t.id;
            children.add(shadcn.MenuButton(
              trailing: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
              child: Text(t.title ?? t.language ?? t.id),
              onPressed: (_) {
                widget.player.setSubtitleTrack(t);
                _startHideTimer();
              },
            ));
            if (i < embeddedTracks.length - 1) {
              children.add(const shadcn.MenuDivider());
            }
          }
        }

        if (externalSubs.isNotEmpty) {
          children.add(const shadcn.MenuDivider());
          for (var i = 0; i < externalSubs.length; i++) {
            final sub = externalSubs[i];
            final selected = _currentSubtitleTrack?.title == sub.displayName;
            children.add(shadcn.MenuButton(
              trailing: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
              child: Text(sub.displayName),
              onPressed: (_) {
                final subUrl = sub.url.startsWith('http')
                    ? sub.url
                    : '${widget.serverUrl ?? ''}${sub.url}';
                widget.player.setSubtitleTrack(
                  SubtitleTrack.uri(subUrl, title: sub.displayName),
                );
                _startHideTimer();
              },
            ));
            if (i < externalSubs.length - 1) {
              children.add(const shadcn.MenuDivider());
            }
          }
        }

        if (embeddedTracks.isEmpty && externalSubs.isEmpty) {
          children.add(shadcn.MenuButton(
            child: const Text('无可用字幕'),
            onPressed: null,
          ));
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(dropdownContext).copyWith(scrollbars: false),
            child: shadcn.DropdownMenu(children: children),
          ),
        );
      },
    );
  }

  Widget _buildPlayControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            BootstrapIcons.skipStartFill,
            color: widget.hasPrevious ? Colors.white : Colors.white38,
            size: 26,
          ),
          onPressed: widget.hasPrevious ? widget.onPrevious : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            _playing ? BootstrapIcons.stopCircleFill : BootstrapIcons.playCircleFill,
            color: Colors.white,
            size: 32,
          ),
          onPressed: () => widget.player.playOrPause(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            BootstrapIcons.skipEndFill,
            color: widget.hasNext ? Colors.white : Colors.white38,
            size: 26,
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
    double size = 26,
  }) {
    final isDesktop = WindowControls.isDesktop;
    final minW = isDesktop ? 48.0 : 40.0;
    final iconWidget = SizedBox(
      width: size,
      height: size,
      child: Center(child: Icon(icon, color: Colors.white, size: size)),
    );
    if (isLast) {
      return Padding(
        padding: EdgeInsets.only(left: (minW - 28) / 2),
        child: GestureDetector(
          key: key,
          onTap: onPressed,
          child: iconWidget,
        ),
      );
    }
    return IconButton(
      key: key,
      icon: iconWidget,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: minW),
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
              _isLocked ? LucideIcons.lock : LucideIcons.lockOpen,
            ),
          ),
        ),
      ),
    );
  }

  void _showPlaylistMenu() async {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return;

    final seasonNumber = episodes.first.seasonNumber;
    final totalEpisodes = episodes.length;
    final currentIndex = widget.currentEpisodeIndex;

    const itemSpacing = 8.0;
    final scrollController = ScrollController();
    final firstItemKey = GlobalKey();
    var didAutoScroll = false;

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (didAutoScroll) return;
          didAutoScroll = true;
          if (!scrollController.hasClients) return;
          final itemExtent = firstItemKey.currentContext?.size?.height ?? 0.0;
          if (itemExtent <= 0) return;
          final viewport = scrollController.position.viewportDimension;
          final target =
              itemExtent * currentIndex - (viewport - itemExtent) / 2;
          final clamped = target.clamp(
            scrollController.position.minScrollExtent,
            scrollController.position.maxScrollExtent,
          );
          scrollController.jumpTo(clamped);
        });
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
                              key: index == 0 ? firstItemKey : null,
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
                                          LucideIcons.circlePlay,
                                          color: Colors.white,
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
          child: Center(child: Icon(widget.icon, color: Colors.white)),
        ),
      ),
    );
  }
}
