import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/window/window_controls.dart';
import 'widgets/player_top_bar.dart';
import '../../data/models/category.dart';
import '../../data/models/episode.dart';
import '../../data/models/storage.dart';
import '../../data/models/subtitle_info.dart';
import '../../data/services/download_service.dart';
import '../../data/services/log_service.dart';
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
  late final Player _player;
  late final VideoController _controller;
  late final Dio _dio;
  bool _isLoading = true;
  String? _error;
  String? _currentStreamUrl; // 当前播放地址，用于错误显示
  String? _currentFilePath; // 当前文件的存储源路径
  bool _isFullscreen = false;
  bool _isDisposing = false;
  bool _isExiting = false;
  int _currentEpisodeIndex = 0;
  Timer? _progressTimer;
  Duration _lastSavedPosition = Duration.zero;
  MediaService? _mediaService;
  bool _hasSeekToInitialPosition = false;
  List<SubtitleInfo> _externalSubtitles = [];
  bool _hasAutoSelectedSubtitle = false;
  bool _externalSubtitleAutoLoaded = false;
  List<Episode>? _episodes;
  double? _sessionPlaybackSpeed;
  int? _pendingSeekPosition;
  bool _hasAppliedPlaybackSettings = false;
  bool _initialLoadStarted = false;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _episodes = widget.episodes;
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    _player = Player();
    _controller = VideoController(_player);
    _initEpisodeIndex();
    _configurePlayerNetwork();
    _setupPlayerListeners();
    _prepareInitialPlayback();
    // 移动端默认进入全屏模式
    if (!WindowControls.isDesktop) {
      _enterFullscreen();
    }
  }

  void _configurePlayerNetwork() {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // 配置 HTTP 流自动重连（暂停后恢复播放时需要）
      platform.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      // 增加网络超时时间
      platform.setProperty('network-timeout', '30');
    }
  }

  void _initEpisodeIndex() {
    if (_episodes != null && widget.type == 'episode') {
      _currentEpisodeIndex = _episodes!.indexWhere(
        (e) => e.id == widget.id,
      );
      if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    }
  }

  Future<void> _loadEpisodesIfNeeded() async {
    if (widget.type != 'episode') return;
    if (_episodes != null) return;
    if (widget.tvShowId == null || widget.seasonId == null) return;

    final episodes = await ref.read(
      seasonEpisodesProvider((tvShowId: widget.tvShowId!, seasonId: widget.seasonId!)).future,
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

  void _applyPlaybackSettings() {
    final speed = _sessionPlaybackSpeed ?? ref.read(playbackSettingsProvider).playbackSpeed;
    _player.setRate(speed);
  }

  void _onSpeedChanged(double speed) {
    _sessionPlaybackSpeed = speed;
  }

  Future<void> _loadEpisodeProgress() async {
    if (widget.type != 'episode' || widget.tvShowId == null) return;
    final episodeId = _currentEpisode?.id;
    if (episodeId == null) return;

    try {
      _mediaService ??= ref.read(mediaServiceProvider);
      final response = await _mediaService!.getEpisodeProgress(
        tvShowId: widget.tvShowId!,
        episodeId: episodeId,
      );
      if (response.success && response.data != null && !response.data!.completed) {
        _pendingSeekPosition = response.data!.position;
      }
    } catch (_) {}
  }

  Future<void> _prepareInitialPlayback() async {
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;

    // 非剧集场景直接走原加载逻辑
    if (widget.type != 'episode') {
      await _loadVideo();
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
      _mediaService ??= ref.read(mediaServiceProvider);
      final response = await _mediaService!.getEpisodeProgress(
        tvShowId: widget.tvShowId!,
        episodeId: episodeId,
      );
      if (response.success && response.data != null) {
        // 返回服务端最新记录（包含 position/duration/completed）
        return response.data;
      }
    } catch (_) {}
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
    if (episodeIndex != null) {
      // 切换剧集触发确认弹窗前先暂停当前播放，避免继续播放干扰选择
      await _player.pause();
    }
    await _loadEpisodesIfNeeded();
    if (!mounted || _isDisposing) return;

    if (widget.type != 'episode') {
      await _loadVideo();
      return;
    }

    if (_episodes == null || _episodes!.isEmpty) {
      // 剧集列表为空时直接按默认逻辑播放
      await _loadVideo();
      return;
    }

    final originalIndex = _currentEpisodeIndex;
    var targetIndex = episodeIndex ?? _currentEpisodeIndex;
    if (targetIndex < 0 || targetIndex >= _episodes!.length) {
      // 目标下标非法，回退到默认加载
      await _loadVideo();
      return;
    }

    // 使用循环处理“下一集仍>90%”的情况，确保每次跳过都会再次提示
    while (true) {
      final episode = _episodeAtIndex(targetIndex);
      if (episode == null) {
        // 下标无法解析到剧集，回退到默认加载
        await _loadVideo();
        return;
      }

      final progressItem = await _fetchEpisodeProgressById(episode.id);
      if (!mounted || _isDisposing) return;

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
          // 用户确认跳下一集：清理待 seek 信息并继续判断下一集
          _pendingSeekPosition = null;
          targetIndex += 1;
          continue;
        }
        // 用户选择继续本集：使用历史进度继续播放
        if (progressItem.position > 0) {
          _pendingSeekPosition = progressItem.position;
        }
      }

      // 未触发提示或用户选择继续本集，开始加载目标剧集
      if (episodeIndex == null && targetIndex == originalIndex) {
        await _loadVideo();
      } else {
        await _loadVideo(episodeIndex: targetIndex);
      }
      return;
    }
  }

  void _setupPlayerListeners() {
    // 监听播放器错误
    _subscriptions.add(_player.stream.error.listen((error) {
      if (!mounted || _isDisposing) return;
      if (error.isNotEmpty) {
        LogService.instance.error('PlayerScreen', 'MPV error: $error, url: $_currentStreamUrl');
        // 过滤非致命的网络/IO错误，这些通常是临时性问题不影响播放
        if (error.contains('Could not open/initialize audio device')) return;
        if (error.contains('ffurl_write')) return;
        if (error.contains('ffurl_read')) return;
        // 使用更精确的 tcp 错误匹配
        if (error.contains('tcp: Connection refused') ||
            error.contains('tcp: Connection reset') ||
            error.contains('tcp: Connection timed out')) {
          return;
        }
        setState(() {
          _error = 'MPV错误: $error\n\n播放地址: ${_currentStreamUrl ?? "未知"}';
          _isLoading = false;
        });
      }
    }));

    // 监听缓冲状态
    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (!mounted || _isDisposing) return;
      // 可选：显示缓冲状态
    }));

    // 监听视频时长，准备好后 seek 到初始位置并设置倍速
    _subscriptions.add(_player.stream.duration.listen((duration) {
      if (!mounted || _isDisposing) return;
      if (duration.inSeconds <= 0) return;

      // 设置倍速（每次视频加载完成后都需要重新设置）
      if (!_hasAppliedPlaybackSettings) {
        _hasAppliedPlaybackSettings = true;
        _applyPlaybackSettings();
      }

      // 优先使用 _pendingSeekPosition（切换视频时设置），否则使用初始位置
      final targetPosition = _pendingSeekPosition ?? widget.initialPosition;
      debugPrint(
        '[PlayerScreen] duration=${duration.inSeconds}s, pendingSeek=$_pendingSeekPosition, initialPosition=${widget.initialPosition}, hasSeek=$_hasSeekToInitialPosition',
      );
      if (!_hasSeekToInitialPosition && targetPosition != null && targetPosition > 0) {
        _hasSeekToInitialPosition = true;
        _pendingSeekPosition = null;
        debugPrint('[PlayerScreen] Seeking to $targetPosition seconds');
        _player.seek(Duration(seconds: targetPosition));
      }
    }));

    // 监听播放完成
    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (!mounted || _isDisposing) return;
      if (completed) {
        unawaited(_saveProgress()); // 播放完成时保存进度
      }
    }));

    // 监听内嵌字幕轨道加载（用于自动选择简体中文字幕）
    _subscriptions.add(_player.stream.tracks.listen((tracks) {
      if (!mounted || _isDisposing) return;
      if (tracks.subtitle.isNotEmpty) {
        _tryAutoSelectEmbeddedSubtitle();
      }
    }));
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_saveProgress());
    });
  }

  Future<void> _saveProgress() async {
    try {
      final position = _player.state.position;
      final duration = _player.state.duration;

      // 跳过无效数据或位置未变化
      if (duration.inSeconds <= 0 || position == _lastSavedPosition) return;
      _lastSavedPosition = position;

      final service = _mediaService;
      if (service == null) return;

      if (widget.type == 'movie') {
        await service.updateWatchProgress(
          mediaType: 'movie',
          mediaId: widget.id,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
      } else if (widget.type == 'episode' && widget.tvShowId != null) {
        final episodeId = _currentEpisode?.id ?? widget.id;
        await service.updateWatchProgress(
          mediaType: 'tv',
          mediaId: widget.tvShowId!,
          episodeId: episodeId,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
      }
    } catch (e) {
      debugPrint('[PlayerScreen] Failed to save progress: $e');
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _progressTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }

    unawaited(_saveProgress()); // 退出时保存最终进度
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
    if (episodeIndex != null) {
      await _player.pause();
      await _saveProgress();
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _currentStreamUrl = null;
      _currentFilePath = null;
      _externalSubtitles = [];
      // 无条件重置，确保重试时也能正确 seek 和设置倍速
      _hasSeekToInitialPosition = false;
      _hasAppliedPlaybackSettings = false;
      _hasAutoSelectedSubtitle = false;
      _externalSubtitleAutoLoaded = false;
      if (episodeIndex != null) {
        _currentEpisodeIndex = episodeIndex;
      } else {
        // 重试场景：清除待 seek 位置，避免使用失败前残留的错误位置
        _pendingSeekPosition = null;
      }
    });

    // 切换视频时获取历史进度
    if (episodeIndex != null) {
      await _loadEpisodeProgress();
    }

    try {
      // 等待下载任务加载完成后再检查本地缓存（最多等待 5 秒）
      var downloadState = ref.read(downloadManagerProvider);
      if (downloadState.isLoading) {
        var waitCount = 0;
        const maxWait = 100; // 100 * 50ms = 5 秒超时
        await Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 50));
          if (!mounted || ++waitCount >= maxWait) return false;
          downloadState = ref.read(downloadManagerProvider);
          return downloadState.isLoading;
        });
      }

      // 检查是否有本地缓存
      String? localPath;

      if (widget.type == 'movie') {
        if (downloadState.isMovieDownloaded(widget.id)) {
          final task = downloadState.getTaskByMovieId(widget.id);
          if (task != null && await File(task.localPath).exists()) {
            localPath = task.localPath;
          }
        }
      } else if (widget.type == 'episode') {
        final episodeId = _currentEpisode?.id ?? widget.id;
        if (downloadState.isEpisodeDownloaded(episodeId)) {
          final task = downloadState.getTaskByEpisodeId(episodeId);
          if (task != null && await File(task.localPath).exists()) {
            localPath = task.localPath;
          }
        }
      }

      if (!mounted) return;

      // 使用本地缓存播放
      if (localPath != null) {
        _currentStreamUrl = localPath;
        await _player.open(Media(localPath));

        if (!mounted) return;

        _mediaService ??= ref.read(mediaServiceProvider);
        _startProgressTimer();
        DialogUtils.showToast(context: context, message: '正在使用本地缓存播放');

        setState(() {
          _isLoading = false;
        });
        return;
      }

      String? streamUrl;
      int? storageId;
      String? filePath;

      if (widget.type == 'movie') {
        final response = await ref.read(movieStreamProvider(widget.id).future);
        streamUrl = response?.url;
        storageId = response?.storageId;
        filePath = response?.filePath;
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
        storageId = response?.storageId;
        filePath = response?.filePath;
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
      final resolvedUrl = await _resolveRedirectTarget(fullUrl);
      final playUrl = resolvedUrl ?? fullUrl;
      final authHeaders = await _buildAuthHeadersForPlayUrl(
        playUrl,
        storageId: storageId,
      );
      final headers = <String, String>{
        'User-Agent': DownloadService.aria2UserAgent,
        ...?authHeaders,
      };

      _currentStreamUrl = playUrl;
      _currentFilePath = filePath;
      await _player.open(Media(playUrl, httpHeaders: headers));

      if (!mounted) return;

      _mediaService ??= ref.read(mediaServiceProvider); // 确保 service 已缓存
      _startProgressTimer(); // 视频加载成功后启动进度保存定时器

      // 加载外挂字幕
      _loadExternalSubtitles(storageId, filePath);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e\n\n播放地址: ${_currentStreamUrl ?? "未知"}';
        _isLoading = false;
      });
    }
  }

  Future<String?> _resolveRedirectTarget(String url) async {
    try {
      // 使用 HEAD 请求避免下载大文件
      final response = await _dio.head(
        url,
        options: Options(
          followRedirects: false,
          validateStatus:
              (status) => status != null && status >= 200 && status < 400,
          headers: const {
            'User-Agent': DownloadService.aria2UserAgent,
          },
        ),
      );

      final code = response.statusCode ?? 0;
      if (code >= 300 && code < 400) {
        final loc = response.headers.value('location');
        if (loc != null && loc.trim().isNotEmpty) {
          return Uri.parse(url).resolve(loc.trim()).toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Storage?> _getStorageById(int storageId) async {
    final current = ref.read(storagesProvider).value;
    if (current != null) {
      try {
        return current.firstWhere((s) => s.id == storageId);
      } catch (_) {}
    }

    await ref.read(storagesProvider.notifier).loadStorages();
    final loaded = ref.read(storagesProvider).value;
    if (loaded == null) return null;
    try {
      return loaded.firstWhere((s) => s.id == storageId);
    } catch (_) {
      return null;
    }
  }

  String _basicAuthHeader(String username, String password) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort && uri.port > 0) return uri.port;
    switch (uri.scheme.toLowerCase()) {
      case 'https':
        return 443;
      case 'http':
        return 80;
      default:
        return uri.port;
    }
  }

  bool _sameOrigin(Uri? a, Uri? b) {
    if (a == null || b == null) return false;
    if (a.scheme.toLowerCase() != b.scheme.toLowerCase()) return false;
    if (a.host.toLowerCase() != b.host.toLowerCase()) return false;
    return _effectivePort(a) == _effectivePort(b);
  }

  Future<Map<String, String>?> _buildAuthHeadersForPlayUrl(
    String playUrl, {
    required int? storageId,
  }) async {
    if (storageId == null) return null;
    final storage = await _getStorageById(storageId);
    if (storage == null) return null;

    if (storage.type.toLowerCase() != 'webdav') return null;
    final settings = storage.settings;
    if (settings == null) return null;

    final webdavUrl = settings['url'];
    final username = settings['username'];
    final password = settings['password'];
    if (webdavUrl == null || username == null || password == null) return null;
    if (username.isEmpty) return null;

    final webdavUri = Uri.tryParse(webdavUrl);
    final playUri = Uri.tryParse(playUrl);

    // 仅当目标 origin 与 WebDAV origin 一致时才附带 BasicAuth，避免把凭证带到 CDN/第三方直链上。
    if (!_sameOrigin(webdavUri, playUri)) return null;
    return {'Authorization': _basicAuthHeader(username, password)};
  }

  Future<void> _loadExternalSubtitles(int? storageId, String? filePath) async {
    if (storageId == null || filePath == null) return;

    final service = _mediaService ?? ref.read(mediaServiceProvider);
    if (service == null) return;

    try {
      final response = await service.getSubtitles(
        storageId: storageId,
        filePath: filePath,
      );
      if (!mounted) return;

      final subtitles = response.data ?? [];
      setState(() {
        _externalSubtitles = subtitles;
      });

      // 自动加载最佳匹配字幕（score >= 85）
      if (subtitles.isNotEmpty) {
        // 找到最高分的字幕
        final bestSub = subtitles.reduce((a, b) => a.score >= b.score ? a : b);
        if (bestSub.score >= 85) {
          final serverUrl = ref.read(serverUrlProvider);
          final subUrl =
              bestSub.url.startsWith('http')
                  ? bestSub.url
                  : '$serverUrl${bestSub.url}';
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(
              subUrl,
              title: bestSub.displayName,
            ),
          );

          // 显示提示
          if (mounted) {
            DialogUtils.showToast(context: context, message: '已自动加载字幕: ${bestSub.displayName}');
            _externalSubtitleAutoLoaded = true;
            _hasAutoSelectedSubtitle = true;
          }
        }
      }
    } catch (e) {
      debugPrint('[PlayerScreen] Failed to load external subtitles: $e');
    }
  }

  SubtitleTrack? _findChineseSubtitleTrack(List<SubtitleTrack> tracks) {
    final validTracks = tracks.where((t) => t.id != 'no' && t.id != 'auto').toList();
    if (validTracks.isEmpty) return null;

    const chineseLanguages = ['zh', 'chi', 'zho', 'zh-cn', 'zh-hans', 'chs', 'sc'];
    const chineseTitleKeywords = ['简体', '简中', 'chs', 'sc', 'simplified', '中文', 'chinese'];

    for (final track in validTracks) {
      final lang = track.language?.toLowerCase() ?? '';
      if (chineseLanguages.contains(lang)) return track;
    }

    for (final track in validTracks) {
      final title = track.title?.toLowerCase() ?? '';
      for (final keyword in chineseTitleKeywords) {
        if (title.contains(keyword.toLowerCase())) return track;
      }
    }

    for (final track in validTracks) {
      final lang = track.language?.toLowerCase() ?? '';
      if (lang.startsWith('zh')) return track;
    }

    return null;
  }

  void _tryAutoSelectEmbeddedSubtitle() {
    if (_hasAutoSelectedSubtitle || _externalSubtitleAutoLoaded) return;

    final tracks = _player.state.tracks.subtitle;
    final chineseTrack = _findChineseSubtitleTrack(tracks);

    if (chineseTrack != null) {
      _hasAutoSelectedSubtitle = true;
      _player.setSubtitleTrack(chineseTrack);
      final displayName = chineseTrack.title ?? chineseTrack.language ?? chineseTrack.id;
      DialogUtils.showToast(context: context, message: '已自动选择内嵌字幕: $displayName');
    }
  }



  Episode? get _currentEpisode {
    if (_episodes == null || _episodes!.isEmpty) return null;
    if (_currentEpisodeIndex < 0 ||
        _currentEpisodeIndex >= _episodes!.length) {
      return null;
    }
    return _episodes![_currentEpisodeIndex];
  }

  bool get _hasPrevious => _episodes != null && _currentEpisodeIndex > 0;
  bool get _hasNext =>
      _episodes != null &&
      _currentEpisodeIndex < _episodes!.length - 1;

  void _playPrevious() {
    if (_hasPrevious) _loadVideo(episodeIndex: _currentEpisodeIndex - 1);
  }

  void _playNext() {
    if (_hasNext) {
      // 点击“下一集”也需要走进度判断与确认逻辑
      unawaited(_prepareEpisodePlayback(
        episodeIndex: _currentEpisodeIndex + 1,
      ));
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _currentStreamUrl == null ? '正在获取播放地址...' : '正在加载视频...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
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

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
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
            ),
            PlayerTopBar(
              title: '播放失败',
              onBack: () => Navigator.of(context).pop(),
              useGradient: false,
              useSafeArea: false,
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
            player: _player,
            controller: _controller,
            title: _displayTitle,
            onBack: () async {
              if (_isExiting) return;
              setState(() => _isExiting = true);
              await _player.pause();
              await _saveProgress();
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
            onSelectEpisode: (index) => _loadVideo(episodeIndex: index),
            externalSubtitles: _externalSubtitles,
            serverUrl: ref.read(serverUrlProvider),
            onSpeedChanged: _onSpeedChanged,
            sourcePath: _currentFilePath,
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
