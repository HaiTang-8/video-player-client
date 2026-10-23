import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../data/models/subtitle_info.dart';
import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import '../engines/playback_engine_factory.dart';
import '../selection/engine_selection_rule.dart';
import '../selection/engine_selector.dart';
import '../selection/platform_environment.dart';
import 'playback_gateways.dart';
import 'playback_item.dart';
import 'playback_progress_tracker.dart';
import 'playback_source_resolver.dart';
import 'playback_startup_timeline.dart';
import 'seek_coordinator.dart';
import 'subtitle_auto_selector.dart';
import 'subtitle_time_shifter.dart';

sealed class PlaybackSessionStatus {
  const PlaybackSessionStatus();
}

final class PlaybackSessionLoading extends PlaybackSessionStatus {
  /// true 表示仍在获取播放地址，false 表示地址已就绪、正在打开视频
  final bool resolvingSource;

  const PlaybackSessionLoading({required this.resolvingSource});
}

final class PlaybackSessionReady extends PlaybackSessionStatus {
  const PlaybackSessionReady();
}

final class PlaybackSessionFailed extends PlaybackSessionStatus {
  final String message;

  const PlaybackSessionFailed(this.message);
}

/// 播放会话门面：管理引擎生命周期与加载流程，UI 只与它和 [engine] 交互
class PlaybackSession extends ChangeNotifier {
  static const _progressInterval = Duration(seconds: 5);

  PlaybackSession({
    required EngineSelector selector,
    required PlaybackEngineFactory factory,
    required PlatformEnvironment environment,
    required PlaybackSourceResolver resolver,
    required PlaybackSourceGateway sourceGateway,
    required WatchProgressGateway progressGateway,
    required double Function() defaultRate,
    EnginePreference enginePreference = EnginePreference.auto,
    SubtitleStyle subtitleStyle = SubtitleStyle.defaults,
    SubtitleDelayStore? subtitleDelayStore,
    Duration videoViewTimeout = const Duration(seconds: 2),
  }) : _selector = selector,
       _factory = factory,
       _environment = environment,
       _progressGateway = progressGateway,
       _resolver = resolver,
       _sourceGateway = sourceGateway,
       _defaultRate = defaultRate,
       _enginePreference = enginePreference,
       _subtitleStyle = subtitleStyle,
       _subtitleDelayStore = subtitleDelayStore,
       _videoViewTimeout = videoViewTimeout {
    _attach(_factory.create(_selectKind()!));
  }

  final EngineSelector _selector;
  final PlaybackEngineFactory _factory;
  final PlatformEnvironment _environment;
  final WatchProgressGateway _progressGateway;
  final PlaybackSourceResolver _resolver;
  final PlaybackSourceGateway _sourceGateway;
  final double Function() _defaultRate;
  final EnginePreference _enginePreference;

  /// 暂停打开后等画面视图挂载的最长时间，超时照常开始播放
  final Duration _videoViewTimeout;
  Timer? _pendingStart;
  final Set<PlaybackEngineKind> _failedKinds = {};
  String _engineReason = '';
  late PlaybackEngine _engine;
  late PlaybackProgressTracker _tracker;
  late SeekCoordinator _seek;

  /// 内核回退后会换成新实例，UI 需要随之重建
  PlaybackEngine get engine => _engine;

  /// 选择当前内核的原因，展示在媒体信息面板
  String get engineReason => _engineReason;
  final SubtitleAutoSelector _subtitleSelector = SubtitleAutoSelector();
  final List<StreamSubscription> _subscriptions = [];
  final StreamController<String> _notices = StreamController.broadcast();

  PlaybackSessionStatus _status = const PlaybackSessionLoading(
    resolvingSource: true,
  );
  PlaybackItem? _item;
  Duration? _startAt;
  bool _rateApplied = false;
  int _loadGeneration = 0;
  String? _currentUrl;
  String? _filePath;
  List<SubtitleInfo> _externalSubtitles = const [];
  double? _sessionRate;
  double? _sessionVolume;
  SubtitleStyle _subtitleStyle;
  final ValueNotifier<Duration> _subtitleDelay = ValueNotifier(Duration.zero);
  Timer? _delayReload;
  final SubtitleDelayStore? _subtitleDelayStore;
  Timer? _delaySave;

  /// 最近一次加载的外挂字幕原文，内核不支持字幕偏移时据此平移后重新加载
  ({SubtitleInfo info, String text})? _externalSubtitle;
  PlaybackStartupTimeline? _startup;
  PlaybackStartupReport? _lastStartup;
  PlaybackSourceObserver? _observer;
  bool _firstFrameNotified = false;
  DateTime? _lastProgressReport;
  bool _disposed = false;

  PlaybackSessionStatus get status => _status;

  /// 当前播放地址（本地路径或网络 URL），用于错误提示
  String? get currentUrl => _currentUrl;

  /// 文件在存储源中的路径
  String? get filePath => _filePath;

  List<SubtitleInfo> get externalSubtitles => _externalSubtitles;

  /// 用户在本次会话中调整过的音量，切换剧集时沿用
  double? get sessionVolume => _sessionVolume;

  /// 字幕偏移按剧集（整部剧共用）或电影保存在本地；没有保存位置时只对当前视频生效
  ValueListenable<Duration> get subtitleDelay => _subtitleDelay;

  /// 偏移由同一部剧的各集共用
  bool get subtitleDelaySharedByShow =>
      _subtitleDelayStore != null && _item is EpisodePlaybackItem;

  /// 内核支持字幕偏移，或当前选中的是可以平移时间轴的外挂字幕
  bool get subtitleDelaySupported =>
      engine.capabilities.subtitleDelay || _externalSelected;

  bool get _externalSelected {
    final external = _externalSubtitle;
    return external != null &&
        engine.state.selectedTracks.subtitle?.title ==
            external.info.displayName;
  }

  bool get isRecoveringFromNetworkError => _tracker.hasRecentNetworkError;

  /// 最近一次加载的起播耗时
  PlaybackStartupReport? get lastStartup => _lastStartup;

  /// 需要提示给用户的消息
  Stream<String> get notices => _notices.stream;

  Future<void> initialize() async {
    try {
      await engine.initialize();
      await engine.setSubtitleStyle(_subtitleStyle);
    } catch (e) {
      LogService.instance.warn(
        'PlaybackSession',
        'Failed to initialize engine: $e',
      );
    }
  }

  /// 切换剧集前调用：保存当前进度并进入加载态
  Future<void> prepareSwitch() async {
    _cancelPendingStart();
    await _seek.awaitActive();
    await engine.pause();
    _reportProgress(engine.state.position, force: true);
    await _tracker.save();
    _setStatus(const PlaybackSessionLoading(resolvingSource: true));
  }

  /// [startAt] 为起播位置，由内核打开时直接定位；非正数视为从头播放
  Future<void> load(PlaybackItem item, {Duration? startAt}) async {
    if (_disposed) return;
    await _seek.awaitActive();
    final generation = ++_loadGeneration;
    _cancelPendingStart();
    if (!identical(item, _item)) {
      _flushDelaySave();
      _subtitleDelay.value = _subtitleDelayStore?.read(item) ?? Duration.zero;
    }
    _delayReload?.cancel();
    _externalSubtitle = null;
    _tracker
      ..stop()
      ..resetErrorTracking();
    _item = item;
    final start =
        (startAt == null || startAt <= Duration.zero) ? null : startAt;
    _startAt = start;
    _rateApplied = false;
    _subtitleSelector.reset();
    _currentUrl = null;
    _filePath = null;
    _externalSubtitles = const [];
    _observer = null;
    _firstFrameNotified = false;
    _lastProgressReport = null;
    _startup = PlaybackStartupTimeline(engine: engine.kind, target: start);
    _setStatus(const PlaybackSessionLoading(resolvingSource: true));

    try {
      final resolved = await _resolver.resolve(item);
      if (_isStale(generation)) return;
      _startup?.markResolved(localFile: resolved.source.isLocalFile);
      _observer = resolved.observer?..onOpening(start);
      _currentUrl = resolved.source.url;
      _filePath = resolved.filePath;
      _setStatus(const PlaybackSessionLoading(resolvingSource: false));

      // 画面在原生视图里的内核先暂停打开，视图挂载后再播放：
      // 页面在 Ready 之后才创建视图，自动播放会在画面显示前先出声（命中缓存时缓冲瞬间完成，尤其明显）
      final waitForView = engine.capabilities.reportsVideoView;
      await engine.open(
        resolved.source,
        autoPlay: !waitForView,
        startPosition: start,
      );
      if (_isStale(generation)) return;
      _startup?.markOpened();
      if (engine.capabilities.subtitleDelay) {
        await _applyToEngine(
          () => engine.setSubtitleDelay(_subtitleDelay.value),
          'subtitle delay',
        );
      }
      final volume = _sessionVolume;
      if (volume != null) await engine.setVolume(volume);
      if (_isStale(generation)) return;

      _tracker.start(item);
      if (start != null) _tracker.markControlledSeek(start);
      if (resolved.source.isLocalFile) {
        _notify('正在使用本地缓存播放');
      } else {
        unawaited(_loadExternalSubtitles(resolved, generation));
      }
      if (waitForView) _armPendingStart();
      _setStatus(const PlaybackSessionReady());
    } on PlaybackSourceUnavailable catch (e) {
      if (!_isStale(generation)) _setStatus(PlaybackSessionFailed('$e'));
    } catch (e) {
      if (_isStale(generation)) return;
      _setStatus(
        PlaybackSessionFailed('加载失败: $e\n\n播放地址: ${_currentUrl ?? "未知"}'),
      );
    }
  }

  /// 重新加载当前项目；尚未生效的起播位置会保留
  Future<void> reload() async {
    final item = _item;
    if (item == null) return;
    await load(item, startAt: _startAt);
  }

  /// 页面层的前置校验失败时调用
  void fail(String message) => _setStatus(PlaybackSessionFailed(message));

  /// 用户发起的 seek，会取消尚未生效的起播位置
  Future<void> seek(Duration position) {
    _startAt = null;
    _observer?.onSeek(position);
    return _seek.seek(position);
  }

  Future<void> awaitActiveSeek() => _seek.awaitActive();

  Future<void> selectExternalSubtitle(SubtitleInfo subtitle) async {
    try {
      final text = await _resolver.fetchSubtitleText(subtitle);
      if (text == null || _disposed) return;
      _externalSubtitle = (info: subtitle, text: text);
      await _addExternalSubtitle(subtitle, text);
    } catch (e) {
      LogService.instance.warn(
        'PlaybackSession',
        'Failed to load subtitle: $e',
      );
    }
  }

  Future<void> _addExternalSubtitle(SubtitleInfo subtitle, String text) {
    final delay = _subtitleDelay.value;
    return engine.addExternalSubtitle(
      ExternalSubtitle.data(
        engine.capabilities.subtitleDelay
            ? text
            : SubtitleTimeShifter.shift(text, delay),
        title: subtitle.displayName,
        formatHint: _formatHint(subtitle.path),
      ),
    );
  }

  void setSubtitleStyle(SubtitleStyle style) {
    if (style == _subtitleStyle) return;
    _subtitleStyle = style;
    unawaited(_applyToEngine(() => engine.setSubtitleStyle(style), 'style'));
  }

  /// 正值表示字幕延后显示。内核不支持时平移外挂字幕时间轴，停止调整后再重新加载
  void setSubtitleDelay(Duration delay) {
    if (_disposed || delay == _subtitleDelay.value) return;
    _subtitleDelay.value = delay;
    _scheduleDelaySave();
    if (engine.capabilities.subtitleDelay) {
      unawaited(
        _applyToEngine(() => engine.setSubtitleDelay(delay), 'subtitle delay'),
      );
      return;
    }
    final external = _externalSubtitle;
    if (external == null || !_externalSelected) return;
    _delayReload?.cancel();
    _delayReload = Timer(const Duration(milliseconds: 600), () {
      if (_disposed || !identical(external, _externalSubtitle)) return;
      unawaited(
        _applyToEngine(
          () => _addExternalSubtitle(external.info, external.text),
          'shifted subtitle',
        ),
      );
    });
  }

  void _scheduleDelaySave() {
    final store = _subtitleDelayStore;
    final item = _item;
    if (store == null || item == null) return;
    _delaySave?.cancel();
    _delaySave = Timer(
      const Duration(milliseconds: 500),
      () => _saveDelay(store, item, _subtitleDelay.value),
    );
  }

  /// 换视频或退出前把尚未写入的偏移立即保存
  void _flushDelaySave() {
    final pending = _delaySave;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    final store = _subtitleDelayStore;
    final item = _item;
    if (store != null && item != null) {
      _saveDelay(store, item, _subtitleDelay.value);
    }
  }

  void _saveDelay(SubtitleDelayStore store, PlaybackItem item, Duration delay) {
    unawaited(
      store.write(item, delay).catchError((Object e) {
        LogService.instance.warn(
          'PlaybackSession',
          'Failed to save subtitle delay: $e',
        );
      }),
    );
  }

  Future<void> _applyToEngine(
    Future<void> Function() action,
    String what,
  ) async {
    try {
      await action();
    } catch (e) {
      LogService.instance.warn('PlaybackSession', 'Failed to apply $what: $e');
    }
  }

  void rememberRate(double rate) => _sessionRate = rate;

  void rememberVolume(double volume) => _sessionVolume = volume;

  /// 退出播放页前调用：等待 seek 结束、暂停并保存进度
  Future<void> prepareExit() async {
    _cancelPendingStart();
    await _seek.awaitActive();
    await engine.pause();
    _reportProgress(engine.state.position, force: true);
    await _tracker.save();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPendingStart();
    _delayReload?.cancel();
    _flushDelaySave();
    _tracker.stop();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _tracker.saveSync();
    _resolver.dispose();
    unawaited(engine.dispose());
    _notices.close();
    super.dispose();
  }

  PlaybackEngineKind? _selectKind() {
    final decision = _selector.select(
      EngineSelectionContext(
        environment: _environment,
        failedKinds: _failedKinds,
        preference: _enginePreference,
      ),
    );
    if (decision.candidates.isEmpty) return null;
    final kind = decision.candidates.first;
    _engineReason = decision.reason;
    LogService.instance.info(
      'PlaybackSession',
      'Playback engine: ${kind.label} (${decision.reason})',
    );
    return kind;
  }

  void _attach(PlaybackEngine engine) {
    _engine = engine;
    _tracker = PlaybackProgressTracker(
      engine: engine,
      gateway: _progressGateway,
      isSeeking: () => _seek.isActive,
    );
    _seek = SeekCoordinator(
      engine: engine,
      onSeekStarted: _tracker.markControlledSeek,
      onSeekSettled: () => _tracker.save(force: true),
    );
    _bindEngine();
  }

  /// 当前内核无法播放时换下一个候选内核，从原位置重新加载；没有候选时返回 false
  bool _tryFallback(PlaybackError error) {
    final item = _item;
    if (item == null) return false;
    final failed = _engine.kind;
    _failedKinds.add(failed);
    final next = _selectKind();
    if (next == null) return false;
    _engineReason = '${failed.label} 无法播放：${error.message}';
    final position = _startAt ?? _engine.state.position;
    _loadGeneration++;
    _tracker.stop();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    final previous = _engine;
    _attach(_factory.create(next));
    unawaited(previous.dispose());
    notifyListeners();
    unawaited(() async {
      await initialize();
      if (_disposed) return;
      _notify('${failed.label} 无法播放（${error.message}），已切换到 ${next.label}');
      await load(item, startAt: position);
    }());
    return true;
  }

  void _bindEngine() {
    final streams = engine.streams;
    _subscriptions
      ..add(streams.errors.listen(_onError))
      ..add(
        streams.position.listen((position) {
          if (_disposed) return;
          _tracker.onPosition(position);
          _reportProgress(position);
          _checkStartup();
        }),
      )
      ..add(
        streams.playing.listen((playing) {
          // 用户在等待期间自己点了播放
          if (playing) _cancelPendingStart();
          _checkStartup();
        }),
      )
      ..add(streams.buffering.listen((_) => _checkStartup()))
      ..add(
        streams.firstFrameRendered.listen((rendered) {
          if (rendered && !_firstFrameNotified) {
            _firstFrameNotified = true;
            _observer?.onFirstFrame();
          }
          _checkStartup();
        }),
      )
      ..add(
        streams.videoViewAttached.listen((attached) {
          if (attached) _startPendingPlayback();
          _checkStartup();
        }),
      )
      ..add(streams.duration.listen(_onDuration))
      ..add(streams.completed.listen(_onCompleted))
      ..add(streams.tracks.listen(_onTracks));
  }

  void _onError(PlaybackError error) {
    if (_disposed) return;
    LogService.instance.error(
      'PlaybackSession',
      '${engine.kind.label} error: $error, url: $_currentUrl',
    );
    // 过滤非致命的网络/IO错误，这些通常是临时性问题不影响播放
    if (error.kind == PlaybackErrorKind.audioOutput) return;
    if (error.recoverable) {
      _tracker.markNetworkError();
      return;
    }
    if (error.fallbackSuggested && _tryFallback(error)) return;
    _setStatus(
      PlaybackSessionFailed(
        '${engine.kind.label} 错误: $error\n\n播放地址: ${_currentUrl ?? "未知"}',
      ),
    );
  }

  /// 时长就绪后应用倍速（每次加载都需要重新设置）；起播位置此时视为已生效
  void _onDuration(Duration duration) {
    if (_disposed || duration.inSeconds <= 0) return;
    if (!_rateApplied) {
      _rateApplied = true;
      engine.setRate(
        math.min(_sessionRate ?? _defaultRate(), engine.capabilities.maxRate),
      );
    }
    LogService.instance.debug(
      'PlaybackSession',
      'duration=${duration.inSeconds}s, startAt=${_startAt?.inSeconds}',
    );
    _startAt = null;
  }

  void _armPendingStart() {
    _pendingStart = Timer(_videoViewTimeout, () {
      LogService.instance.warn(
        'PlaybackSession',
        'video view not attached within ${_videoViewTimeout.inMilliseconds}ms, starting anyway',
      );
      _startPendingPlayback();
    });
    if (engine.state.videoViewAttached) _startPendingPlayback();
  }

  void _startPendingPlayback() {
    if (_pendingStart == null || _disposed) return;
    _cancelPendingStart();
    if (!engine.state.playing) unawaited(engine.play());
  }

  void _cancelPendingStart() {
    _pendingStart?.cancel();
    _pendingStart = null;
  }

  /// 每 5 秒把播放位置告诉片源一侧（缓存据此估算续播点）；[force] 用于退出和切换剧集
  void _reportProgress(Duration position, {bool force = false}) {
    final observer = _observer;
    final duration = engine.state.duration;
    if (observer == null || duration <= Duration.zero) return;
    final now = DateTime.now();
    final last = _lastProgressReport;
    if (!force && last != null && now.difference(last) < _progressInterval) {
      return;
    }
    _lastProgressReport = now;
    observer.onProgress(position, duration);
  }

  void _checkStartup() {
    final report = _startup?.onState(engine.state);
    if (_disposed || report == null) return;
    _startup = null;
    _lastStartup = report;
    LogService.instance.info('PlaybackSession', 'startup $report');
  }

  void _onCompleted(bool completed) {
    if (_disposed || !completed) return;
    if (_tracker.isSuspiciousCompletion()) {
      LogService.instance.warn(
        'PlaybackSession',
        'Ignored suspicious completed after network error',
      );
      return;
    }
    unawaited(_tracker.save(fromCompleted: true));
  }

  void _onTracks(MediaTracks tracks) {
    if (_disposed || tracks.subtitle.isEmpty) return;
    final track = _subtitleSelector.takeEmbedded(tracks.subtitle);
    if (track == null) return;
    engine.selectSubtitleTrack(track);
    _notify('已自动选择内嵌字幕: ${track.title ?? track.language ?? track.id}');
  }

  Future<void> _loadExternalSubtitles(
    ResolvedPlayback resolved,
    int generation,
  ) async {
    final storageId = resolved.storageId;
    final filePath = resolved.filePath;
    if (storageId == null || filePath == null) return;
    try {
      final subtitles = await _sourceGateway.listSubtitles(
        storageId: storageId,
        filePath: filePath,
      );
      if (_isStale(generation)) return;
      _externalSubtitles = subtitles;
      notifyListeners();

      final best = _subtitleSelector.bestExternal(subtitles);
      if (best == null) return;
      await selectExternalSubtitle(best);
      if (_isStale(generation)) return;
      _subtitleSelector.markDone();
      _notify('已自动加载字幕: ${best.displayName}');
    } catch (e) {
      LogService.instance.warn(
        'PlaybackSession',
        'Failed to load external subtitles: $e',
      );
    }
  }

  static String? _formatHint(String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    return extension.isEmpty ? null : extension;
  }

  bool _isStale(int generation) => _disposed || generation != _loadGeneration;

  void _setStatus(PlaybackSessionStatus status) {
    if (_disposed) return;
    if (status is PlaybackSessionFailed) _startup = null;
    _status = status;
    notifyListeners();
  }

  void _notify(String message) {
    if (!_disposed) _notices.add(message);
  }
}
