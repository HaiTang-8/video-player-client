import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/dialog_utils.dart';
import '../../core/window/window_controls.dart';
import 'widgets/player_top_bar.dart';
import 'widgets/buffering_ring_indicator.dart';
import '../../data/models/category.dart';
import '../../data/models/episode.dart';
import '../../data/services/log_service.dart';
import '../../providers/providers.dart';
import '../../playback/cache/proxied_source_resolver.dart';
import '../../playback/playback_providers.dart';
import '../../playback/session/playback_item.dart';
import '../../playback/session/playback_session.dart';
import '../../playback/session/playback_source_resolver.dart';
import '../../playback/session/riverpod_playback_gateway.dart';
import 'widgets/custom_video_controls.dart';

/// 视频播放器页面
class PlayerScreen extends ConsumerStatefulWidget {
  final String type; // 'movie' or 'episode'
  final int id;
  final int? tvShowId;
  final int? seasonId;
  final String? title;
  final List<Episode>? episodes;
  final int? initialPosition; // 初始播放位置（秒）

  const PlayerScreen({
    super.key,
    required this.type,
    required this.id,
    this.tvShowId,
    this.seasonId,
    this.title,
    this.episodes,
    this.initialPosition,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlaybackSession _session;
  late final StreamSubscription<String> _noticeSubscription;
  bool _isFullscreen = false;
  bool _isDisposing = false;
  bool _isExiting = false;
  int _currentEpisodeIndex = 0;
  List<Episode>? _episodes;
  int? _routeInitialPosition;
  bool _initialLoadStarted = false;

  @override
  void initState() {
    super.initState();
    _episodes = widget.episodes;
    _session = _createSession();
    _session.addListener(_onSessionChanged);
    _noticeSubscription = _session.notices.listen((message) {
      if (mounted) DialogUtils.showToast(context: context, message: message);
    });
    _routeInitialPosition = widget.initialPosition;
    _initEpisodeIndex();
    _prepareInitialPlayback();
    // 移动端默认进入全屏模式
    if (!WindowControls.isDesktop) {
      _enterFullscreen();
    }
  }

  PlaybackSession _createSession() {
    final gateway = RiverpodPlaybackGateway(ref);
    return PlaybackSession(
      selector: ref.read(engineSelectorProvider),
      factory: ref.read(playbackEngineFactoryProvider),
      environment: ref.read(platformEnvironmentProvider),
      resolver: ProxiedSourceResolver.wrapIfEnabled(
        PlaybackSourceResolver(gateway),
        quotaGb: ref.read(playbackSettingsProvider).cacheQuotaGb,
        serverUrl: () => gateway.serverUrl,
        findDownloadedFile: gateway.findDownloadedFile,
      ),
      sourceGateway: gateway,
      progressGateway: gateway,
      defaultRate: () => ref.read(playbackSettingsProvider).playbackSpeed,
      enginePreference: ref.read(playbackSettingsProvider).enginePreference,
      subtitleStyle: ref.read(subtitleSettingsProvider),
      subtitleDelayStore: gateway,
    );
  }

  void _onSessionChanged() {
    if (mounted && !_isDisposing) setState(() {});
  }

  @override
  void dispose() {
    _isDisposing = true;
    _noticeSubscription.cancel();
    _session.removeListener(_onSessionChanged);
    // 会话销毁时会同步保存最后一次进度
    _session.dispose();
    if (_isFullscreen) {
      _exitFullscreen();
    }
    super.dispose();
  }

  void _initEpisodeIndex() {
    if (_episodes != null && widget.type == 'episode') {
      _currentEpisodeIndex = _episodes!.indexWhere((e) => e.id == widget.id);
      if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    }
  }

  Future<void> _loadEpisodesIfNeeded() async {
    if (widget.type != 'episode') return;
    if (_episodes != null) return;
    if (widget.tvShowId == null || widget.seasonId == null) return;

    final episodes = await ref.read(
      seasonEpisodesProvider((
        tvShowId: widget.tvShowId!,
        seasonId: widget.seasonId!,
      )).future,
    );
    if (!mounted) return;
    if (episodes != null) {
      setState(() {
        _episodes = episodes;
        _currentEpisodeIndex = episodes.indexWhere((e) => e.id == widget.id);
        if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
      });
    }
  }

  int? _normalizeSeekPosition(int? position) {
    if (position == null || position <= 0) return null;
    return position;
  }

  int? _extractResumePosition(WatchHistoryItem? item) {
    if (item == null || item.completed) return null;
    return _normalizeSeekPosition(item.position);
  }

  Future<int?> _loadEpisodeProgress() async {
    if (widget.type != 'episode' || widget.tvShowId == null) return null;
    final episodeId = _currentEpisode?.id;
    if (episodeId == null) return null;

    try {
      final service = ref.read(mediaServiceProvider);
      if (service == null) return null;
      final response = await service.getEpisodeProgress(
        tvShowId: widget.tvShowId!,
        episodeId: episodeId,
      );
      if (response.success && response.data != null) {
        return _extractResumePosition(response.data);
      }
    } catch (e) {
      LogService.instance.warn(
        'PlayerScreen',
        'Failed to load episode progress: $e',
      );
    }
    return null;
  }

  Future<void> _prepareInitialPlayback() async {
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    await _session.initialize();
    if (!mounted || _isDisposing) return;

    // 非剧集场景直接加载
    if (widget.type != 'episode') {
      await _loadCurrent(startAtSeconds: _routeInitialPosition);
      return;
    }

    // 剧集场景统一走“播放前判断”流程
    await _prepareEpisodePlayback();
  }

  Future<WatchHistoryItem?> _fetchEpisodeProgressById(int episodeId) async {
    // 仅在剧集场景下获取指定剧集的播放进度，用于“>90%”提示判断
    if (widget.type != 'episode' || widget.tvShowId == null) return null;
    try {
      // 通过 MediaService 拉取指定剧集的观看历史
      final service = ref.read(mediaServiceProvider);
      if (service == null) return null;
      final response = await service.getEpisodeProgress(
        tvShowId: widget.tvShowId!,
        episodeId: episodeId,
      );
      if (response.success && response.data != null) {
        // 返回服务端最新记录（包含 position/duration/completed）
        return response.data;
      }
    } catch (e) {
      LogService.instance.warn(
        'PlayerScreen',
        'Failed to fetch episode progress: $e',
      );
    }
    return null;
  }

  Episode? _episodeAtIndex(int index) {
    // 根据下标安全读取剧集，避免越界导致异常
    final episodes = _episodes;
    if (episodes == null || episodes.isEmpty) return null;
    if (index < 0 || index >= episodes.length) return null;
    return episodes[index];
  }

  bool _hasNextForIndex(int index) {
    // 独立判断指定下标是否存在下一集，用于多次“跳下一集”确认
    final episodes = _episodes;
    if (episodes == null || episodes.isEmpty) return false;
    return index >= 0 && index < episodes.length - 1;
  }

  Future<void> _prepareEpisodePlayback({int? episodeIndex}) async {
    // 统一处理“播放当前/下一集”前的进度判断与确认逻辑
    await _session.awaitActiveSeek();
    if (episodeIndex != null) {
      // 切换剧集触发确认弹窗前先暂停当前播放，避免继续播放干扰选择
      await _session.engine.pause();
    }
    await _loadEpisodesIfNeeded();
    if (!mounted || _isDisposing) return;

    if (widget.type != 'episode') {
      await _loadCurrent(startAtSeconds: _routeInitialPosition);
      return;
    }

    if (_episodes == null || _episodes!.isEmpty) {
      // 剧集列表为空时直接按默认逻辑播放
      await _loadCurrent(startAtSeconds: _routeInitialPosition);
      return;
    }

    final originalIndex = _currentEpisodeIndex;
    var targetIndex = episodeIndex ?? _currentEpisodeIndex;
    if (targetIndex < 0 || targetIndex >= _episodes!.length) {
      // 目标下标非法，回退到默认加载
      await _loadCurrent(startAtSeconds: _routeInitialPosition);
      return;
    }

    // 使用循环处理“下一集仍>90%”的情况，确保每次跳过都会再次提示
    while (true) {
      final episode = _episodeAtIndex(targetIndex);
      if (episode == null) {
        // 下标无法解析到剧集，回退到默认加载
        await _loadCurrent(startAtSeconds: _routeInitialPosition);
        return;
      }

      final progressItem = await _fetchEpisodeProgressById(episode.id);
      if (!mounted || _isDisposing) return;
      final hasRouteInitialPosition =
          episodeIndex == null &&
          targetIndex == originalIndex &&
          _normalizeSeekPosition(_routeInitialPosition) != null;
      final resumePosition = _extractResumePosition(progressItem);
      final startAtSeconds =
          hasRouteInitialPosition ? _routeInitialPosition : resumePosition;

      // 仅当存在下一集且当前集进度>90%时才提示
      final shouldPrompt =
          _hasNextForIndex(targetIndex) &&
          progressItem != null &&
          progressItem.duration > 0 &&
          progressItem.progress > 0.9;
      if (shouldPrompt) {
        // 在用户确认之前不加载视频，必须做出选择
        final goNext = await DialogUtils.showConfirmDialog(
          context: context,
          title: '提示',
          // 使用真实剧集名称替换“当前集”提示，便于用户识别
          content: '${episode.displayTitle} 已观看超过 90%，是否直接播放下一集？',
          cancelText: '继续本集',
          confirmText: '播放下一集',
          barrierDismissible: false,
        );
        if (!mounted || _isDisposing) return;
        if (goNext == true) {
          // 用户确认跳下一集：清理路由起播位置并继续判断下一集
          _routeInitialPosition = null;
          targetIndex += 1;
          continue;
        }
      }

      // 未触发提示或用户选择继续本集，开始加载目标剧集
      if (episodeIndex == null && targetIndex == originalIndex) {
        await _loadCurrent(startAtSeconds: startAtSeconds);
      } else {
        await _switchEpisode(targetIndex);
      }
      return;
    }
  }

  PlaybackItem? get _currentItem {
    if (widget.type == 'movie') return MoviePlaybackItem(widget.id);
    if (widget.type == 'episode' &&
        widget.tvShowId != null &&
        widget.seasonId != null) {
      return EpisodePlaybackItem(
        tvShowId: widget.tvShowId!,
        seasonId: widget.seasonId!,
        episodeId: _currentEpisode?.id ?? widget.id,
      );
    }
    return null;
  }

  Future<void> _loadCurrent({int? startAtSeconds}) async {
    final item = _currentItem;
    if (item == null) {
      _session.fail('无法获取播放地址');
      return;
    }
    await _session.load(
      item,
      startAt:
          startAtSeconds == null ? null : Duration(seconds: startAtSeconds),
    );
  }

  /// 切换到指定剧集，从该集的历史进度开始播放
  Future<void> _switchEpisode(int index) async {
    await _session.prepareSwitch();
    if (!mounted || _isDisposing) return;
    setState(() {
      _currentEpisodeIndex = index;
      _routeInitialPosition = null;
    });
    final resumePosition = await _loadEpisodeProgress();
    if (!mounted || _isDisposing) return;
    await _loadCurrent(startAtSeconds: resumePosition);
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

  Episode? get _currentEpisode {
    if (_episodes == null || _episodes!.isEmpty) return null;
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= _episodes!.length) {
      return null;
    }
    return _episodes![_currentEpisodeIndex];
  }

  bool get _hasPrevious => _episodes != null && _currentEpisodeIndex > 0;
  bool get _hasNext =>
      _episodes != null && _currentEpisodeIndex < _episodes!.length - 1;

  void _playPrevious() {
    if (_hasPrevious) _switchEpisode(_currentEpisodeIndex - 1);
  }

  void _playNext() {
    if (_hasNext) {
      // 点击“下一集”也需要走进度判断与确认逻辑
      unawaited(
        _prepareEpisodePlayback(episodeIndex: _currentEpisodeIndex + 1),
      );
    }
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
    final playbackSettings = ref.watch(playbackSettingsProvider);
    ref.listen(
      subtitleSettingsProvider,
      (_, style) => _session.setSubtitleStyle(style),
    );

    final status = _session.status;
    if (status is PlaybackSessionLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            BufferingRingIndicator(
              label: status.resolvingSource ? '正在获取播放地址' : '正在加载视频',
            ),
            PlayerTopBar(
              title: _displayTitle.isNotEmpty ? _displayTitle : '加载中...',
              onBack: () => Navigator.of(context).pop(),
              useGradient: false,
              useSafeArea: true,
            ),
          ],
        ),
      );
    }

    if (status is PlaybackSessionFailed) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 56),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              status.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          shadcn.PrimaryButton(
                            onPressed: _session.reload,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(shadcn.LucideIcons.refreshCw, size: 16),
                                SizedBox(width: 8),
                                Text('重试'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          shadcn.OutlineButton(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: status.message),
                              );
                              DialogUtils.showToast(
                                context: context,
                                message: '已复制错误信息',
                              );
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(shadcn.LucideIcons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('复制'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PlayerTopBar(
              title: '播放失败',
              onBack: () => Navigator.of(context).pop(),
              useGradient: false,
              useSafeArea: true,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomVideoControls(
            // 内核回退时引擎换成新实例，控制层随之重建
            key: ObjectKey(_session.engine),
            engine: _session.engine,
            engineReason: _session.engineReason,
            title: _displayTitle,
            onBack: () async {
              if (_isExiting) return;
              setState(() => _isExiting = true);
              await _session.prepareExit();
              if (context.mounted) Navigator.of(context).pop();
            },
            onPrevious: _hasPrevious ? _playPrevious : null,
            onNext: _hasNext ? _playNext : null,
            hasPrevious: _hasPrevious,
            hasNext: _hasNext,
            onToggleFullscreen: _toggleFullscreen,
            isFullscreen: _isFullscreen,
            episodes: _episodes,
            currentEpisodeIndex: _currentEpisodeIndex,
            onSelectEpisode: _switchEpisode,
            externalSubtitles: _session.externalSubtitles,
            serverUrl: ref.read(serverUrlProvider),
            onSpeedChanged: _session.rememberRate,
            initialVolume: _session.sessionVolume,
            onVolumeChanged: _session.rememberVolume,
            sourcePath: _session.filePath,
            onSelectExternalSubtitle: _session.selectExternalSubtitle,
            subtitleDelay: _session.subtitleDelay,
            subtitleDelaySupported: () => _session.subtitleDelaySupported,
            subtitleDelaySharedByShow: _session.subtitleDelaySharedByShow,
            onSubtitleDelayChanged: _session.setSubtitleDelay,
            onSeekRequested: _session.seek,
            isPlaybackErrorRecoveryActive:
                () => _session.isRecoveringFromNetworkError,
            seekDuration: playbackSettings.seekDuration,
            longPressSpeed: playbackSettings.longPressSpeed,
          ),
          if (_isExiting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
