import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/episode.dart';
import '../../data/services/media_service.dart';
import '../../providers/providers.dart';
import 'widgets/custom_video_controls.dart';

/// 视频播放器页面
class PlayerScreen extends ConsumerStatefulWidget {
  final String type; // 'movie' or 'episode'
  final int id;
  final int? tvShowId;
  final int? seasonId;
  final String? title;
  final List<Episode>? episodes;

  const PlayerScreen({
    super.key,
    required this.type,
    required this.id,
    this.tvShowId,
    this.seasonId,
    this.title,
    this.episodes,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isLoading = true;
  String? _error;
  bool _isFullscreen = false;
  bool _isDisposing = false;
  int _currentEpisodeIndex = 0;
  Timer? _progressTimer;
  Duration _lastSavedPosition = Duration.zero;
  MediaService? _mediaService;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _initEpisodeIndex();
    _applyPlaybackSettings();
    _setupPlayerListeners();
    _loadVideo();
    // 移动端默认进入全屏模式
    if (!WindowControls.isDesktop) {
      _enterFullscreen();
    }
  }

  void _initEpisodeIndex() {
    if (widget.episodes != null && widget.type == 'episode') {
      _currentEpisodeIndex = widget.episodes!.indexWhere((e) => e.id == widget.id);
      if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    }
  }

  void _applyPlaybackSettings() {
    final settings = ref.read(playbackSettingsProvider);
    _player.setRate(settings.playbackSpeed);
  }

  void _setupPlayerListeners() {
    // 监听播放器错误
    _player.stream.error.listen((error) {
      if (!mounted || _isDisposing) return;
      if (error.isNotEmpty) {
        setState(() {
          _error = '播放错误: $error';
          _isLoading = false;
        });
      }
    });

    // 监听缓冲状态
    _player.stream.buffering.listen((buffering) {
      if (!mounted || _isDisposing) return;
      // 可选：显示缓冲状态
    });

    // 监听播放完成
    _player.stream.completed.listen((completed) {
      if (!mounted || _isDisposing) return;
      if (completed) {
        _saveProgress(); // 播放完成时保存进度
      }
    });
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveProgress();
    });
  }

  void _saveProgress() {
    final position = _player.state.position;
    final duration = _player.state.duration;

    // 跳过无效数据或位置未变化
    if (duration.inSeconds <= 0 || position == _lastSavedPosition) return;
    _lastSavedPosition = position;

    final service = _mediaService;
    if (service == null) return;

    if (widget.type == 'movie') {
      service.updateWatchProgress(
        mediaType: 'movie',
        mediaId: widget.id,
        position: position.inSeconds,
        duration: duration.inSeconds,
      );
    } else if (widget.type == 'episode' && widget.tvShowId != null) {
      final episodeId = _currentEpisode?.id ?? widget.id;
      service.updateWatchProgress(
        mediaType: 'tv',
        mediaId: widget.tvShowId!,
        episodeId: episodeId,
        position: position.inSeconds,
        duration: duration.inSeconds,
      );
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _progressTimer?.cancel();
    _saveProgress(); // 退出时保存最终进度
    if (_isFullscreen) {
      _exitFullscreen();
    }
    _player.dispose();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _isFullscreen = true;
    });
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted && !_isDisposing) {
      setState(() {
        _isFullscreen = false;
      });
    }
  }

  void _toggleFullscreen() {
    if (WindowControls.isDesktop) {
      WindowControls.toggleFullscreen();
      setState(() => _isFullscreen = !_isFullscreen);
    } else {
      if (_isFullscreen) {
        _exitFullscreen();
      } else {
        _enterFullscreen();
      }
    }
  }

  Future<void> _loadVideo({int? episodeIndex}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      if (episodeIndex != null) _currentEpisodeIndex = episodeIndex;
    });

    try {
      String? streamUrl;

      if (widget.type == 'movie') {
        final response = await ref.read(movieStreamProvider(widget.id).future);
        streamUrl = response?.url;
      } else if (widget.type == 'episode' &&
          widget.tvShowId != null &&
          widget.seasonId != null) {
        final episodeId = _currentEpisode?.id ?? widget.id;
        final response = await ref.read(
          episodeStreamProvider((
            tvShowId: widget.tvShowId!,
            seasonId: widget.seasonId!,
            episodeId: episodeId,
          )).future,
        );
        streamUrl = response?.url;
      }

      if (!mounted) return;

      if (streamUrl == null || streamUrl.isEmpty) {
        setState(() {
          _error = '无法获取播放地址';
          _isLoading = false;
        });
        return;
      }

      // 获取服务器地址
      final serverUrl = ref.read(serverUrlProvider);
      final fullUrl =
          streamUrl.startsWith('http') ? streamUrl : '$serverUrl$streamUrl';
          
      await _player.open(Media(fullUrl));

      if (!mounted) return;
      _mediaService ??= ref.read(mediaServiceProvider); // 确保 service 已缓存
      _startProgressTimer(); // 视频加载成功后启动进度保存定时器
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Episode? get _currentEpisode {
    if (widget.episodes == null || widget.episodes!.isEmpty) return null;
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= widget.episodes!.length) return null;
    return widget.episodes![_currentEpisodeIndex];
  }

  bool get _hasPrevious => widget.episodes != null && _currentEpisodeIndex > 0;
  bool get _hasNext => widget.episodes != null && _currentEpisodeIndex < widget.episodes!.length - 1;

  void _playPrevious() {
    if (_hasPrevious) _loadVideo(episodeIndex: _currentEpisodeIndex - 1);
  }

  void _playNext() {
    if (_hasNext) _loadVideo(episodeIndex: _currentEpisodeIndex + 1);
  }

  String get _displayTitle {
    if (widget.type == 'episode' && _currentEpisode != null) {
      return _currentEpisode!.displayTitle;
    }
    return widget.title ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const LoadingWidget(message: '加载中...'),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar:
            WindowControls.isDesktop
                ? DesktopTitleBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  // Desktop 端自绘标题栏：返回按钮使用“<”样式，标题不居中。
                  centerTitle: false,
                  leading: AppBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: const Text('播放失败'),
                )
                : AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  toolbarHeight: 44,
                  centerTitle: false,
                  automaticallyImplyLeading: false,
                  leadingWidth: kAppBackButtonWidth,
                  titleSpacing: 1,
                  leading: AppBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                    color: Colors.white,
                  ),
                  title: const Text(
                    '播放失败',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadVideo,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomVideoControls(
        player: _player,
        controller: _controller,
        title: _displayTitle,
        onBack: () => Navigator.of(context).pop(),
        onPrevious: _hasPrevious ? _playPrevious : null,
        onNext: _hasNext ? _playNext : null,
        hasPrevious: _hasPrevious,
        hasNext: _hasNext,
        onToggleFullscreen: _toggleFullscreen,
        isFullscreen: _isFullscreen,
      ),
    );
  }
}
