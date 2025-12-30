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
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  bool _visible = true;
  Timer? _hideTimer;
  bool _dragging = false;
  double _brightness = 0.5;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  bool _showSeekOverlay = false;
  Duration _seekPosition = Duration.zero;
  Duration _seekStartPosition = Duration.zero;
  bool _wasPlayingBeforeSeek = false;

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
    _focusNode.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleVisibility() {
    setState(() {
      _visible = !_visible;
      if (_visible) _startHideTimer();
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, bool isLeft) {
    if (WindowControls.isDesktop) return;
    final delta = -details.delta.dy / 200;
    setState(() {
      if (isLeft) {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        _showBrightnessOverlay = true;
        ScreenBrightness().setApplicationScreenBrightness(_brightness);
      } else {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        _showVolumeOverlay = true;
        widget.player.setVolume(_volume * 100);
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details, bool isLeft) {
    setState(() {
      if (isLeft) {
        _showBrightnessOverlay = false;
      } else {
        _showVolumeOverlay = false;
      }
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (WindowControls.isDesktop) return;
    _wasPlayingBeforeSeek = _playing;
    if (_playing) widget.player.pause();
    setState(() {
      _seekStartPosition = _position;
      _seekPosition = _position;
      _showSeekOverlay = true;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (WindowControls.isDesktop) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx / screenWidth * _duration.inMilliseconds;
    setState(() {
      _seekPosition = Duration(
        milliseconds: (_seekPosition.inMilliseconds + delta.toInt())
            .clamp(0, _duration.inMilliseconds),
      );
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (WindowControls.isDesktop) return;
    widget.player.seek(_seekPosition);
    if (_wasPlayingBeforeSeek) widget.player.play();
    setState(() => _showSeekOverlay = false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!WindowControls.isDesktop) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // 右箭头长按倍速
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent && event is! KeyRepeatEvent) {
        _startLongPressSpeed();
      } else if (event is KeyUpEvent) {
        _endLongPressSpeed();
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
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: WindowControls.isDesktop,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: _toggleVisibility,
            onLongPressStart: WindowControls.isDesktop ? null : (_) => _startLongPressSpeed(),
            onLongPressEnd: WindowControls.isDesktop ? null : (_) => _endLongPressSpeed(),
            behavior: HitTestBehavior.translucent,
            child: Video(controller: widget.controller, controls: NoVideoControls),
          ),
          // 左侧亮度手势区域
          if (!WindowControls.isDesktop)
            Positioned(
              left: 0,
              top: 60,
              bottom: 100,
              width: MediaQuery.of(context).size.width * 0.3,
              child: GestureDetector(
                onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, true),
                onVerticalDragEnd: (d) => _onVerticalDragEnd(d, true),
                behavior: HitTestBehavior.translucent,
              ),
            ),
          // 右侧音量手势区域
          if (!WindowControls.isDesktop)
            Positioned(
              right: 0,
              top: 60,
              bottom: 100,
              width: MediaQuery.of(context).size.width * 0.3,
              child: GestureDetector(
                onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, false),
                onVerticalDragEnd: (d) => _onVerticalDragEnd(d, false),
                behavior: HitTestBehavior.translucent,
              ),
            ),
          // 中间水平滑动进度区域
          if (!WindowControls.isDesktop)
            Positioned(
              left: MediaQuery.of(context).size.width * 0.3,
              right: MediaQuery.of(context).size.width * 0.3,
              top: 60,
              bottom: 100,
              child: GestureDetector(
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                behavior: HitTestBehavior.translucent,
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
            _buildBottomBar(),
            _buildProgressBar(),
          ],
          // 缓冲指示器
          if (_buffering)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          // 长按倍速提示
          if (_isLongPressSpeed)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              _volume > 0.5 ? Icons.volume_up : (_volume > 0 ? Icons.volume_down : Icons.volume_off),
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
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
        child: SafeArea(
          bottom: false,
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: SizedBox(
                height: WindowControls.isMacOS ? 52 : 44,
                child: Row(
                  children: [
                    if (WindowControls.isMacOS) const SizedBox(width: 72),
                    AppBackButton(onPressed: onBack, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final bottomPadding = WindowControls.isDesktop ? 0.0 : MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 56 + bottomPadding,
      child: Row(
        children: [
          Text(
            _formatDuration(_position),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                activeColor: Colors.red,
                inactiveColor: Colors.white38,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_duration),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          left: 8,
          right: 8,
          top: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            // 左侧：音量 + 倍速（桌面端）
            if (WindowControls.isDesktop) _buildVolumeControl(),
            if (WindowControls.isDesktop) _buildSpeedButton(),
            const Spacer(),
            // 中间：播放控制
            _buildPlayControls(),
            const Spacer(),
            // 右侧：音轨 + 字幕 + 列表
            _buildIconButton(Icons.audiotrack, () => _showAudioTrackSheet()),
            _buildIconButton(
              Icons.closed_caption_outlined,
              () => _showSubtitleSheet(),
            ),
            if (widget.episodes != null && widget.episodes!.isNotEmpty)
              _buildIconButton(Icons.playlist_play, _showPlaylistMenu),
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
            size: 22,
          ),
          onPressed: () {
            widget.player.setVolume(_volume == 0 ? 100 : 0);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36),
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

  Widget _buildSpeedButton() {
    return TextButton(
      onPressed: _showSpeedSheet,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
      ),
      child: Text(
        '${_playbackSpeed}x',
        style: const TextStyle(color: Colors.white, fontSize: 13),
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
            size: 28,
          ),
          onPressed: widget.hasPrevious ? widget.onPrevious : null,
        ),
        const SizedBox(width: 8),
        IconButton(
          iconSize: 44,
          icon: Icon(
            _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
          ),
          onPressed: () => widget.player.playOrPause(),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            Icons.skip_next,
            color: widget.hasNext ? Colors.white : Colors.white38,
            size: 28,
          ),
          onPressed: widget.hasNext ? widget.onNext : null,
        ),
      ],
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback? onPressed, {
    GlobalKey? key,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, color: Colors.white, size: 22),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40),
    );
  }

  Widget _buildCheckMark() {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: const Icon(Icons.check, color: Colors.black, size: 10),
    );
  }

  void _showSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
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
    final panelWidth = WindowControls.isDesktop ? 200.0 : MediaQuery.of(context).size.width * 0.6;
    final result = await showGeneralDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, _, __) {
        final currentId = _currentSubtitleTrack?.id;
        final embeddedTracks = _subtitleTracks.where((t) => t.id != 'no').toList();
        final externalSubs = widget.externalSubtitles;

        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: Material(
              color: Colors.black87,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text('字幕', style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        )),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8),
                          children: [
                            ListTile(
                              dense: true,
                              title: const Text('关闭', style: TextStyle(color: Colors.white, fontSize: 14)),
                              trailing: currentId == 'no' || currentId == null
                                  ? _buildCheckMark()
                                  : null,
                              onTap: () => Navigator.pop(ctx, SubtitleTrack.no()),
                            ),
                            if (embeddedTracks.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text('内嵌字幕', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              ),
                              ...embeddedTracks.map(
                                (t) => ListTile(
                                  dense: true,
                                  title: Text(t.title ?? t.language ?? t.id,
                                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  trailing: currentId == t.id
                                      ? _buildCheckMark()
                                      : null,
                                  onTap: () => Navigator.pop(ctx, t),
                                ),
                              ),
                            ],
                            if (externalSubs.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text('外挂字幕', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              ),
                              ...externalSubs.map(
                                (sub) => ListTile(
                                  dense: true,
                                  title: Text(sub.displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  trailing: currentId == 'external_${sub.path}'
                                      ? _buildCheckMark()
                                      : null,
                                  onTap: () => Navigator.pop(ctx, {'external': sub}),
                                ),
                              ),
                            ],
                            if (embeddedTracks.isEmpty && externalSubs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('无可用字幕', style: TextStyle(color: Colors.white38)),
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
        final subUrl = sub.url.startsWith('http')
            ? sub.url
            : '${widget.serverUrl ?? ''}${sub.url}';
        widget.player.setSubtitleTrack(SubtitleTrack.uri(subUrl, title: sub.displayName));
      }
    }
    _startHideTimer();
  }

  void _showAudioTrackMenu() async {
    final panelWidth = WindowControls.isDesktop ? 200.0 : MediaQuery.of(context).size.width * 0.6;
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
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: Material(
              color: Colors.black87,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text('音轨', style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        )),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8),
                          children: [
                            ..._audioTracks.where((t) => t.id != 'no').map(
                                  (t) => ListTile(
                                    dense: true,
                                    title: Text(t.title ?? t.language ?? t.id,
                                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                                    trailing: currentId == t.id
                                        ? _buildCheckMark()
                                        : null,
                                    onTap: () => Navigator.pop(ctx, t),
                                  ),
                                ),
                            if (_audioTracks.where((t) => t.id != 'no').isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('无可用音轨', style: TextStyle(color: Colors.white38)),
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

    final panelWidth = WindowControls.isDesktop ? 280.0 : MediaQuery.of(context).size.width * 0.7;
    final result = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: Material(
              color: Colors.black87,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text('选集', style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        )),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: episodes.length,
                          itemBuilder: (_, index) {
                            final ep = episodes[index];
                            final isCurrent = index == widget.currentEpisodeIndex;
                            return ListTile(
                              dense: true,
                              title: Text(
                                ep.displayTitle,
                                style: TextStyle(
                                  color: isCurrent ? Colors.red : Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: isCurrent ? _buildCheckMark() : null,
                              onTap: () => Navigator.pop(ctx, index),
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
    if (result != null && result != widget.currentEpisodeIndex) {
      widget.onSelectEpisode?.call(result);
    }
    _startHideTimer();
  }
}
