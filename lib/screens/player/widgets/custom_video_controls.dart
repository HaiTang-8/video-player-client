import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart'
    as shadcn
    show
        AlertDialog,
        DropdownMenu,
        MenuButton,
        MenuDivider,
        MenuItem,
        PrimaryButton,
        Theme,
        ThemeData,
        showDropdown;
import 'package:shadcn_flutter/shadcn_flutter.dart'
    show LucideIcons, BootstrapIcons;
import '../../../core/widgets/dialog_utils.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/episode.dart';
import '../../../data/models/subtitle_info.dart';
import '../../../data/services/log_service.dart';
import 'player_top_bar.dart';
import 'player_overlay_notice.dart';
import 'ripple_loading_indicator.dart';

class _PlayerHelpEntry {
  final String action;
  final List<String> triggers;

  const _PlayerHelpEntry(this.action, this.triggers);
}

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
  final String? sourcePath;
  final Future<void> Function(SubtitleInfo sub)? onSelectExternalSubtitle;
  final Future<void> Function(Duration position)? onSeekRequested;

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
    this.sourcePath,
    this.onSelectExternalSubtitle,
    this.onSeekRequested,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls>
    with WidgetsBindingObserver {
  static const double _maxVolume = 2.0;

  // iOS 横屏下 SafeArea/viewPadding 可能是“左右对称”的（例如 Dynamic Island 机型），
  // 仅凭 inset 无法判断刘海到底在左还是在右。为了满足“刘海在右侧才给播放列表右侧留安全距离”
  // 的需求，这里通过原生接口读取真实的 UIInterfaceOrientation。
  static const MethodChannel _orientationChannel = MethodChannel(
    'media_player/orientation',
  );

  // 是否判定“刘海在右侧”。用于播放列表弹层的右侧安全距离计算。
  // - iOS：由原生 UIInterfaceOrientation 决定（landscapeRight => true）。
  // - 其他平台：兜底使用 viewPadding 的左右大小对比。
  final ValueNotifier<bool> _notchOnRight = ValueNotifier<bool>(false);
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
  int _seekRequestVersion = 0;
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

  // 倍速切换提示
  bool _showSpeedHint = false;
  double _hintSpeed = 1.0;
  Timer? _speedHintTimer;

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
  Timer? _volumeOverlayTimer;

  // 三指点击触发媒体信息
  int _pointerCount = 0;
  bool _threeFingerTriggered = false;

  final List<StreamSubscription> _subscriptions = [];
  final FocusNode _focusNode = FocusNode();
  double _volumeBeforeMute = 1.0;

  Timer? _speedTimer;
  String? _speedText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBrightness();
    _initCurrentTracks();
    _setupListeners();
    _startHideTimer();

    // 首帧后刷新一次刘海方向（避免 initState 时 MediaQuery 还没就绪）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshNotchSide());
    });
  }

  Future<void> _initBrightness() async {
    if (WindowControls.isDesktop) return;
    try {
      _brightness = await ScreenBrightness().application;
    } catch (e) {
      LogService.instance.warn('VideoControls', 'Failed to get brightness: $e');
    }
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
        if (!mounted) return;
        setState(() => _buffering = b);
        if (b) {
          _startSpeedPolling();
        } else {
          _stopSpeedPolling();
        }
      }),
    );
    _subscriptions.add(
      widget.player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = (v / 100).clamp(0.0, _maxVolume));
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

  void _startSpeedPolling() {
    _speedTimer?.cancel();
    _speedTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      final platform = widget.player.platform;
      if (platform is! NativePlayer || !mounted) return;
      try {
        final raw = await platform.getProperty('cache-speed');
        final bytes = double.tryParse(raw) ?? 0;
        if (!mounted) return;
        setState(() {
          _speedText = bytes > 0 ? _formatSpeed(bytes) : null;
        });
      } catch (e) {
        LogService.instance.warn(
          'VideoControls',
          'Failed to get cache-speed: $e',
        );
      }
    });
  }

  void _stopSpeedPolling() {
    _speedTimer?.cancel();
    _speedTimer = null;
    if (mounted) setState(() => _speedText = null);
  }

  static String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(0)} KB/s';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB/s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notchOnRight.dispose();
    _hideTimer?.cancel();
    _longPressTimer?.cancel();
    _mediaInfoTimer?.cancel();
    _volumeOverlayTimer?.cancel();
    _speedHintTimer?.cancel();
    _speedTimer?.cancel();
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
      } catch (e) {
        LogService.instance.warn(
          'VideoControls',
          'Failed to reset brightness: $e',
        );
      }
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 旋转屏幕/系统 UI 变化会触发 metrics 变化。这里刷新一次刘海方向，确保弹层也能动态更新。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshNotchSide());
    });
  }

  bool _guessNotchOnRightByInsets(EdgeInsets vp) {
    // Android/部分机型：刘海在右侧时 viewPadding.right 通常会大于 left。
    // iOS（尤其 Dynamic Island 机型）可能左右相等，这个兜底无法区分左右。
    return vp.right > vp.left;
  }

  Future<bool?> _fetchNotchOnRightFromPlatform() async {
    if (kIsWeb || WindowControls.isDesktop) return null;
    if (!Platform.isIOS && !Platform.isAndroid) return null;

    // 优先使用原生直接返回“刘海在左/右”的判断：
    // - iOS：通过 UIInterfaceOrientation 推断（并按用户实测修正映射）
    // - Android：优先从 DisplayCutout 的位置推断（部分机型 viewPadding 可能左右对称，无法区分）
    try {
      final side = await _orientationChannel.invokeMethod<String>(
        'getNotchSide',
      );
      switch (side) {
        case 'right':
          return true;
        case 'left':
          return false;
        case 'none':
          return false;
        default:
          return null;
      }
    } catch (_) {
      // 兼容旧版本：iOS 先前只实现了 getInterfaceOrientation。
      if (!Platform.isIOS) return null;
      try {
        final orientation = await _orientationChannel.invokeMethod<String>(
          'getInterfaceOrientation',
        );
        switch (orientation) {
          // 注意：iOS 的 UIInterfaceOrientation 与“顶部（刘海）在屏幕哪一侧”的直觉容易相反。
          // 以用户反馈为准：当前实现反了，因此这里对调映射：
          // - landscapeLeft  => 刘海在右侧
          // - landscapeRight => 刘海在左侧
          case 'landscapeLeft':
            return true; // 顶部（刘海）在右侧
          case 'landscapeRight':
            return false; // 顶部（刘海）在左侧
          default:
            return null;
        }
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _refreshNotchSide() async {
    if (!mounted) return;
    final mq = MediaQuery.maybeOf(context);
    final vp = mq?.viewPadding ?? EdgeInsets.zero;

    final platformValue = await _fetchNotchOnRightFromPlatform();
    final next = platformValue ?? _guessNotchOnRightByInsets(vp);
    if (_notchOnRight.value != next) {
      _notchOnRight.value = next;
    }
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
    if (_panDirection == null &&
        (_panAccumulatedDx > 10 || _panAccumulatedDy > 10)) {
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
        _panDirection =
            _panStartPosition!.dx < screenWidth / 2
                ? 'vertical_left'
                : 'vertical_right';
      }
    }

    if (_panDirection == null) return;

    if (_panDirection == 'horizontal') {
      final screenWidth = MediaQuery.of(context).size.width;
      final delta =
          details.delta.dx / screenWidth * _duration.inMilliseconds * 0.3;
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
      if (_panDirection == 'vertical_left') {
        setState(() {
          _brightness = (_brightness + delta).clamp(0.0, 1.0);
          _showBrightnessOverlay = true;
          _brightnessChanged = true;
        });
        try {
          ScreenBrightness().setApplicationScreenBrightness(_brightness);
        } catch (e) {
          LogService.instance.warn(
            'VideoControls',
            'Failed to set brightness: $e',
          );
        }
      } else {
        _volumeOverlayTimer?.cancel();
        _setVolume(_volume + delta);
        setState(() => _showVolumeOverlay = true);
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (WindowControls.isDesktop) return;

    if (_panDirection == 'horizontal') {
      unawaited(
        _commitSeek(
          _seekPosition,
          resumeAfterSeek: _wasPlayingBeforeSeek,
          hideSeekOverlay: true,
        ),
      );
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
    } else if (key == LogicalKeyboardKey.keyH ||
        key == LogicalKeyboardKey.question ||
        key == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.isShiftPressed) {
      _showShortcutHelp();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<_PlayerHelpEntry> _desktopHelpEntries() {
    return const [
      _PlayerHelpEntry('播放 / 暂停', ['Space']),
      _PlayerHelpEntry('后退 5 秒', ['←']),
      _PlayerHelpEntry('前进 5 秒', ['→']),
      _PlayerHelpEntry('临时 2 倍速', ['长按 →']),
      _PlayerHelpEntry('音量增加', ['↑']),
      _PlayerHelpEntry('音量降低', ['↓']),
      _PlayerHelpEntry('静音 / 取消静音', ['M']),
      _PlayerHelpEntry('全屏 / 退出全屏', ['F']),
      _PlayerHelpEntry('退出全屏', ['Esc']),
      _PlayerHelpEntry('下一集', ['N']),
      _PlayerHelpEntry('上一集', ['P']),
      _PlayerHelpEntry('媒体信息', ['Tab']),
      _PlayerHelpEntry('2 倍速锁定', ['D']),
      _PlayerHelpEntry('打开此说明', ['H', '?']),
    ];
  }

  List<_PlayerHelpEntry> _mobileHelpEntries() {
    return const [
      _PlayerHelpEntry('显示 / 隐藏控制栏', ['点击屏幕']),
      _PlayerHelpEntry('拖动播放进度', ['横向滑动']),
      _PlayerHelpEntry('调节亮度', ['左侧上下滑动']),
      _PlayerHelpEntry('调节音量', ['右侧上下滑动']),
      _PlayerHelpEntry('临时 2 倍速', ['长按屏幕']),
      _PlayerHelpEntry('媒体信息', ['三指点击']),
      _PlayerHelpEntry('锁定 / 解锁控制栏', ['锁定按钮']),
      _PlayerHelpEntry('选择播放集数', ['播放列表按钮']),
    ];
  }

  Future<void> _showShortcutHelp() {
    _hideTimer?.cancel();
    setState(() => _visible = true);

    final isDesktop = WindowControls.isDesktop;
    final entries = isDesktop ? _desktopHelpEntries() : _mobileHelpEntries();
    return DialogUtils.showCustomDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = shadcn.Theme.of(dialogContext);
        final mq = MediaQuery.of(dialogContext);
        final compact = mq.size.width < 600;
        final dialogWidth = compact ? mq.size.width * 0.9 : 720.0;
        final maxHeight = mq.size.height * (compact ? 0.72 : 0.68);

        return SizedBox(
          width: dialogWidth,
          child: shadcn.AlertDialog(
            barrierColor: Colors.transparent,
            surfaceOpacity: 1,
            title: Row(
              children: [
                Icon(
                  isDesktop ? LucideIcons.keyboard : LucideIcons.circleHelp,
                  size: 20,
                  color: theme.colorScheme.foreground,
                ),
                const SizedBox(width: 8),
                Text(isDesktop ? '快捷键说明' : '手势说明'),
              ],
            ),
            content: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: _buildHelpEntries(entries, theme, compact),
                ),
              ),
            ),
            actions: [
              shadcn.PrimaryButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) _startHideTimer();
    });
  }

  Widget _buildHelpEntries(
    List<_PlayerHelpEntry> entries,
    shadcn.ThemeData theme,
    bool compact,
  ) {
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _buildHelpEntry(entries[i], theme, true),
            if (i < entries.length - 1)
              Divider(height: 1, color: theme.colorScheme.border),
          ],
        ],
      );
    }

    final splitIndex = (entries.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildHelpEntryColumn(entries.sublist(0, splitIndex), theme),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _buildHelpEntryColumn(entries.sublist(splitIndex), theme),
        ),
      ],
    );
  }

  Widget _buildHelpEntryColumn(
    List<_PlayerHelpEntry> entries,
    shadcn.ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _buildHelpEntry(entries[i], theme, false),
          if (i < entries.length - 1)
            Divider(height: 1, color: theme.colorScheme.border),
        ],
      ],
    );
  }

  Widget _buildHelpEntry(
    _PlayerHelpEntry entry,
    shadcn.ThemeData theme,
    bool compact,
  ) {
    final action = Text(
      entry.action,
      style: theme.typography.small.copyWith(
        color: theme.colorScheme.foreground,
        fontWeight: FontWeight.w500,
      ),
    );
    final triggers = Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: [
        for (final trigger in entry.triggers) _buildHelpTrigger(trigger, theme),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [action, const SizedBox(height: 8), triggers],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: action),
          const SizedBox(width: 16),
          Flexible(child: triggers),
        ],
      ),
    );
  }

  Widget _buildHelpTrigger(String text, shadcn.ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Text(
        text,
        style: theme.typography.small.copyWith(
          color: theme.colorScheme.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
    unawaited(_commitSeek(clamped, showControlsAfterSeek: true));
  }

  Future<void> _commitSeek(
    Duration target, {
    bool resumeAfterSeek = false,
    bool hideSeekOverlay = false,
    bool showControlsAfterSeek = false,
    bool restartHideTimer = false,
  }) async {
    final seekRequestVersion = ++_seekRequestVersion;
    setState(() {
      _position = target;
      _dragging = true;
    });

    try {
      final onSeekRequested = widget.onSeekRequested;
      if (onSeekRequested != null) {
        await onSeekRequested(target);
      } else {
        await Future<void>.sync(() => widget.player.seek(target));
      }
      if (resumeAfterSeek && seekRequestVersion == _seekRequestVersion) {
        await Future<void>.sync(() => widget.player.play());
      }
    } finally {
      if (mounted) {
        final isLatestSeek = seekRequestVersion == _seekRequestVersion;
        setState(() {
          if (isLatestSeek) {
            _position = target;
            _dragging = false;
          }
          if (hideSeekOverlay) {
            _showSeekOverlay = false;
          }
        });
        if (isLatestSeek) {
          if (showControlsAfterSeek) {
            _showControlsTemporarily();
          } else if (restartHideTimer) {
            _startHideTimer();
          }
        }
      }
    }
  }

  void _adjustVolume(double delta) {
    _setVolume(_volume + delta);
    _showVolumeOverlayTemporarily();
    _showControlsTemporarily();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      final restoreVolume = _volumeBeforeMute <= 0 ? 1.0 : _volumeBeforeMute;
      _setVolume(restoreVolume);
    }
    _showVolumeOverlayTemporarily();
    _showControlsTemporarily();
  }

  void _setVolume(double value) {
    final volume = value.clamp(0.0, _maxVolume);
    setState(() => _volume = volume);
    widget.player.setVolume(volume * 100);
  }

  void _showVolumeOverlayTemporarily() {
    _volumeOverlayTimer?.cancel();
    setState(() => _showVolumeOverlay = true);
    _volumeOverlayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showVolumeOverlay = false);
    });
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

  void _showSpeedChangeHint(double speed) {
    _speedHintTimer?.cancel();
    setState(() {
      _hintSpeed = speed;
      _showSpeedHint = true;
    });
    _speedHintTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showSpeedHint = false);
    });
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
        info['采样率'] =
            sr != null ? '${(sr / 1000).toStringAsFixed(1)} kHz' : sampleRate;
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

      // 源路径
      if (widget.sourcePath != null && widget.sourcePath!.isNotEmpty) {
        info['源路径'] = widget.sourcePath!;
      }

      if (mounted) setState(() => _mediaInfo = info);
    } catch (e) {
      LogService.instance.warn(
        'VideoControls',
        'Failed to fetch media info: $e',
      );
    }
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
            Listener(
              onPointerDown:
                  WindowControls.isDesktop
                      ? null
                      : (_) {
                        _pointerCount++;
                        if (_pointerCount >= 3 && !_threeFingerTriggered) {
                          _threeFingerTriggered = true;
                          _toggleMediaInfo();
                        }
                      },
              onPointerUp:
                  WindowControls.isDesktop
                      ? null
                      : (_) {
                        _pointerCount = (_pointerCount - 1).clamp(0, 10);
                        if (_pointerCount == 0) _threeFingerTriggered = false;
                      },
              onPointerCancel:
                  WindowControls.isDesktop
                      ? null
                      : (_) {
                        _pointerCount = (_pointerCount - 1).clamp(0, 10);
                        if (_pointerCount == 0) _threeFingerTriggered = false;
                      },
              child: GestureDetector(
                onTap: () {
                  if (WindowControls.isDesktop) {
                    widget.player.playOrPause();
                    _showControlsTemporarily();
                  } else {
                    _toggleVisibility();
                  }
                },
                onDoubleTap:
                    WindowControls.isDesktop ? widget.onToggleFullscreen : null,
                onLongPressStart:
                    WindowControls.isDesktop || _isLocked
                        ? null
                        : (_) => _startLongPressSpeed(),
                onLongPressEnd:
                    WindowControls.isDesktop || _isLocked
                        ? null
                        : (_) => _endLongPressSpeed(),
                onPanStart:
                    WindowControls.isDesktop || _isLocked ? null : _onPanStart,
                onPanUpdate:
                    WindowControls.isDesktop || _isLocked ? null : _onPanUpdate,
                onPanEnd:
                    WindowControls.isDesktop || _isLocked ? null : _onPanEnd,
                behavior: HitTestBehavior.translucent,
                child: Video(
                  controller: widget.controller,
                  controls: NoVideoControls,
                  fit: _isFillMode ? BoxFit.cover : BoxFit.contain,
                ),
              ),
            ),
            if (_showBrightnessOverlay) _buildBrightnessOverlay(),
            if (_showVolumeOverlay) _buildVolumeOverlay(),
            if (_showSeekOverlay) _buildSeekOverlay(),
            // 媒体信息面板
            if (_showMediaInfo) _buildMediaInfoPanel(),
            // 控制栏
            if (_visible) ...[
              PlayerTopBar(
                title: widget.title ?? '',
                onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
                isLocked: _isLocked,
              ),
              if (!_isLocked) _buildBottomBar(),
              _buildProgressBar(),
            ],
            // 锁定按钮（仅移动端）
            if (_visible && !WindowControls.isDesktop) _buildLockButton(),
            // 缓冲指示器
            if (_buffering)
              RippleLoadingIndicator(speedText: _speedText, hintText: '缓冲中'),
            if (_isLongPressSpeed)
              PlayerOverlayNotice(
                text: '倍速中 2x',
                position: PlayerOverlayNoticePosition.top,
                safePadding: MediaQuery.of(context).padding,
              ),
            if (_showSpeedHint && !_isLongPressSpeed)
              PlayerOverlayNotice(
                text: '${_hintSpeed}x',
                position: PlayerOverlayNoticePosition.top,
                safePadding: MediaQuery.of(context).padding,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrightnessOverlay() {
    return PlayerOverlayNotice(
      icon: _brightness > 0.5 ? LucideIcons.sun : LucideIcons.moon,
      text: '${(_brightness * 100).round()}%',
      progress: _brightness,
    );
  }

  Widget _buildVolumeOverlay() {
    final boosted = _volume > 1.0;
    return PlayerOverlayNotice(
      icon:
          _volume > 0.5
              ? LucideIcons.volume2
              : (_volume > 0 ? LucideIcons.volume1 : LucideIcons.volumeX),
      text: '${(_volume * 100).round()}%',
      progress: _volume / _maxVolume,
      color: boosted ? Colors.redAccent : Colors.white,
    );
  }

  String _formatSeekDelta(Duration delta) {
    final isNegative = delta.isNegative;
    final abs = delta.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final s = abs.inSeconds.remainder(60);
    final prefix = isNegative ? '-' : '+';
    if (h > 0) return '$prefix$h小时$m分钟$s秒';
    if (m > 0) return '$prefix$m分钟$s秒';
    return '$prefix$s秒';
  }

  Widget _buildSeekOverlay() {
    final delta = _seekPosition - _seekStartPosition;
    return PlayerOverlayNotice(
      text: _formatSeekDelta(delta),
      secondaryText:
          '${_formatDuration(_seekPosition)} / ${_formatDuration(_duration)}',
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: IgnorePointer(
              ignoring: _isLocked,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _isLocked ? 0 : 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value:
                      _duration.inMilliseconds > 0
                          ? (_position.inMilliseconds /
                                  _duration.inMilliseconds)
                              .clamp(0.0, 1.0)
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
                    final target = Duration(
                      milliseconds: (v * _duration.inMilliseconds).round(),
                    );
                    unawaited(_commitSeek(target, restartHideTimer: true));
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
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
                    _buildSubtitleButton(),
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      _buildIconButton(
                        LucideIcons.list,
                        _showPlaylistMenu,
                        isLast: !WindowControls.isDesktop,
                        size: 30,
                      ),
                    if (WindowControls.isDesktop)
                      _buildIconButton(
                        widget.isFullscreen
                            ? LucideIcons.minimize
                            : LucideIcons.maximize,
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
            _toggleMute();
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
              max: _maxVolume,
              onChanged: (v) {
                _setVolume(v);
                _showVolumeOverlayTemporarily();
              },
              activeColor: _volume > 1.0 ? Colors.redAccent : Colors.white,
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
      builder:
          (menuContext) => GestureDetector(
            onTap: () {
              _hideTimer?.cancel();
              _showSpeedMenu(menuContext, speeds);
            },
            child: Padding(
              padding: EdgeInsets.only(right: isDesktop ? 0 : 8),
              child: Container(
                constraints:
                    isDesktop ? const BoxConstraints(minWidth: 48) : null,
                alignment: isDesktop ? Alignment.center : null,
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
      margin:
          isMobile
              ? EdgeInsets.only(
                left: padding.left,
                right: padding.right,
                top: padding.top,
                bottom: padding.bottom,
              )
              : null,
      builder: (dropdownContext) {
        final noAccentTheme = shadcn.Theme.of(dropdownContext).copyWith(
          colorScheme:
              () => shadcn.Theme.of(
                dropdownContext,
              ).colorScheme.copyWith(accent: () => Colors.transparent),
        );
        final children = <shadcn.MenuItem>[];
        for (var i = 0; i < speeds.length; i++) {
          final s = speeds[i];
          final selected = (_playbackSpeed - s).abs() < 0.01;
          children.add(
            shadcn.MenuButton(
              trailing:
                  selected
                      ? const Icon(Icons.check, size: 16, color: Colors.black)
                      : null,
              child: Text('${s}x'),
              onPressed: (_) {
                widget.player.setRate(s);
                widget.onSpeedChanged?.call(s);
                _showSpeedChangeHint(s);
                _startHideTimer();
              },
            ),
          );
          if (i < speeds.length - 1) {
            children.add(const shadcn.MenuDivider());
          }
        }
        return shadcn.Theme(
          data: noAccentTheme,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                dropdownContext,
              ).copyWith(scrollbars: false),
              child: shadcn.DropdownMenu(children: children),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioTrackButton({bool isLast = false}) {
    return Builder(
      builder:
          (menuContext) => GestureDetector(
            onTap: () {
              _hideTimer?.cancel();
              _showAudioTrackMenu(menuContext);
            },
            child: Padding(
              padding: EdgeInsets.only(left: isLast ? 6 : 0),
              child: const SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: Icon(
                    LucideIcons.audioLines,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
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
      margin:
          isMobile
              ? EdgeInsets.only(
                left: padding.left,
                right: padding.right,
                top: padding.top,
                bottom: padding.bottom,
              )
              : null,
      builder: (dropdownContext) {
        final noAccentTheme = shadcn.Theme.of(dropdownContext).copyWith(
          colorScheme:
              () => shadcn.Theme.of(
                dropdownContext,
              ).colorScheme.copyWith(accent: () => Colors.transparent),
        );
        if (tracks.isEmpty) {
          return shadcn.Theme(
            data: noAccentTheme,
            child: shadcn.DropdownMenu(
              children: [
                shadcn.MenuButton(onPressed: null, child: const Text('无可用音轨')),
              ],
            ),
          );
        }
        final children = <shadcn.MenuItem>[];
        for (var i = 0; i < tracks.length; i++) {
          final t = tracks[i];
          final selected = _currentAudioTrack?.id == t.id;
          children.add(
            shadcn.MenuButton(
              trailing:
                  selected
                      ? const Icon(Icons.check, size: 16, color: Colors.black)
                      : null,
              child: Text(t.title ?? t.language ?? t.id),
              onPressed: (_) {
                widget.player.setAudioTrack(t);
                _startHideTimer();
              },
            ),
          );
          if (i < tracks.length - 1) {
            children.add(const shadcn.MenuDivider());
          }
        }
        return shadcn.Theme(
          data: noAccentTheme,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                dropdownContext,
              ).copyWith(scrollbars: false),
              child: shadcn.DropdownMenu(children: children),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubtitleButton() {
    return Builder(
      builder:
          (menuContext) => GestureDetector(
            onTap: () {
              _hideTimer?.cancel();
              _showSubtitleMenu(menuContext);
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: const SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: Icon(
                    LucideIcons.captions,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
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
      margin:
          isMobile
              ? EdgeInsets.only(
                left: padding.left,
                right: padding.right,
                top: padding.top,
                bottom: padding.bottom,
              )
              : null,
      builder: (dropdownContext) {
        final noAccentTheme = shadcn.Theme.of(dropdownContext).copyWith(
          colorScheme:
              () => shadcn.Theme.of(
                dropdownContext,
              ).colorScheme.copyWith(accent: () => Colors.transparent),
        );
        final closeSelected = currentId == 'no' || currentId == null;
        final children = <shadcn.MenuItem>[
          shadcn.MenuButton(
            trailing:
                closeSelected
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
            children.add(
              shadcn.MenuButton(
                trailing:
                    selected
                        ? const Icon(Icons.check, size: 16, color: Colors.black)
                        : null,
                child: Text(t.title ?? t.language ?? t.id),
                onPressed: (_) {
                  widget.player.setSubtitleTrack(t);
                  _startHideTimer();
                },
              ),
            );
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
            children.add(
              shadcn.MenuButton(
                trailing:
                    selected
                        ? const Icon(Icons.check, size: 16, color: Colors.black)
                        : null,
                child: Text(sub.displayName),
                onPressed: (_) {
                  widget.onSelectExternalSubtitle?.call(sub);
                  _startHideTimer();
                },
              ),
            );
            if (i < externalSubs.length - 1) {
              children.add(const shadcn.MenuDivider());
            }
          }
        }

        if (embeddedTracks.isEmpty && externalSubs.isEmpty) {
          children.add(
            shadcn.MenuButton(onPressed: null, child: const Text('无可用字幕')),
          );
        }

        return shadcn.Theme(
          data: noAccentTheme,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                dropdownContext,
              ).copyWith(scrollbars: false),
              child: shadcn.DropdownMenu(children: children),
            ),
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
            _playing
                ? BootstrapIcons.stopCircleFill
                : BootstrapIcons.playCircleFill,
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
        child: GestureDetector(key: key, onTap: onPressed, child: iconWidget),
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
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isLocked ? LucideIcons.lock : LucideIcons.lockOpen,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _showPlaylistMenu() async {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return;

    // 打开播放列表前先刷新一次刘海方向，确保初次展示就是正确的安全距离。
    await _refreshNotchSide();
    if (!mounted) return;

    final seasonNumber = episodes.first.seasonNumber;
    final totalEpisodes = episodes.length;
    final currentIndex = widget.currentEpisodeIndex;

    const itemSpacing = 8.0;
    final scrollController = ScrollController();
    final firstItemKey = GlobalKey();
    var didAutoScroll = false;

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
            child: Builder(
              builder: (innerCtx) {
                final mq = MediaQuery.of(innerCtx);
                final panelWidth =
                    WindowControls.isDesktop ? 280.0 : mq.size.width * 0.35;
                final vp = mq.viewPadding;
                // 这里不要直接用 SafeArea：
                // - 在 Android 沉浸式全屏(immersiveSticky)下，MediaQuery.padding 可能被系统置为 0，
                //   SafeArea 会“看起来失效”，导致播放列表内容贴到屏幕边缘/刘海区域。
                // - MediaQuery.viewPadding 会保留“物理屏幕不可用区域”(刘海/圆角等)的 inset，
                //   更适合用来做全屏播放器的安全距离计算。
                //
                // 需求：播放列表面板固定在屏幕右侧：
                // - 刘海在右侧：右边需要安全距离（避免被刘海遮挡）。
                // - 刘海在左侧：右边不需要安全距离（尽量铺满到屏幕右边）。
                //
                // iOS 有些机型横屏时左右 inset 可能相等（系统为了对称），仅靠 inset 不能判断刘海左右，
                // 因此在 iOS 上通过原生 UIInterfaceOrientation 判定刘海方向。
                return ValueListenableBuilder<bool>(
                  valueListenable: _notchOnRight,
                  builder: (context, notchOnRight, _) {
                    final isLandscape = mq.orientation == Orientation.landscape;
                    final needRightSafe =
                        isLandscape && notchOnRight && vp.right > 0;
                    final safePadding = EdgeInsets.only(
                      top: vp.top,
                      bottom: vp.bottom,
                      right: needRightSafe ? vp.right : 0,
                    );
                    return Material(
                      color: const Color(0xFF1C1C1E),
                      child: SizedBox(
                        width: panelWidth,
                        height: double.infinity,
                        child: Padding(
                          padding: safePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  10,
                                ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                    );
                  },
                );
              },
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
