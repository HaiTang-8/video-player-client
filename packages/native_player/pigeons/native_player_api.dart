import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/native_player_api.g.dart',
    swiftOut:
        'darwin/native_player/Sources/native_player/NativePlayerApi.g.swift',
    kotlinOut:
        'android/src/main/kotlin/com/mediaserver/nativeplayer/NativePlayerApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.mediaserver.nativeplayer'),
    dartPackageName: 'native_player',
  ),
)
class NativeCapabilities {
  NativeCapabilities({
    required this.dolbyVisionColor,
    required this.maxVolume,
    required this.maxRate,
  });

  bool dolbyVisionColor;

  /// 1.0 = 100%
  double maxVolume;
  double maxRate;
}

class NativeSource {
  NativeSource({
    required this.url,
    required this.httpHeaders,
    required this.isLocalFile,
    this.startPositionMs,
  });

  String url;
  Map<String, String> httpHeaders;
  bool isLocalFile;

  /// 起播位置，内核打开时直接定位；null 表示从头播放
  int? startPositionMs;
}

class NativeTrack {
  NativeTrack({required this.id, this.title, this.language});

  String id;
  String? title;
  String? language;
}

enum NativeDynamicRange { unknown, sdr, hdr10, hdr10Plus, hlg, dolbyVision }

class NativeVideoInfo {
  NativeVideoInfo({required this.dynamicRange, this.dolbyVisionProfile});

  NativeDynamicRange dynamicRange;
  int? dolbyVisionProfile;
}

/// 媒体信息面板数据；details 为内核专属项，键为展示名
class NativeDiagnostics {
  NativeDiagnostics({
    this.videoDecoder,
    this.outputDynamicRange,
    required this.details,
  });

  String? videoDecoder;

  /// 实际送显的动态范围，SDR 表示 HDR 片源已被映射为 SDR
  NativeDynamicRange? outputDynamicRange;
  Map<String, String> details;
}

enum NativeVideoFit { contain, cover }

enum NativeErrorKind { network, http, audioOutput, source, decoder, unknown }

class NativeError {
  NativeError({
    required this.kind,
    required this.message,
    this.httpStatus,
    required this.recoverable,
    required this.fallbackSuggested,
  });

  NativeErrorKind kind;
  String message;
  int? httpStatus;
  bool recoverable;

  /// 当前内核无法播放此媒体（如设备不能解码杜比视界 P5、缺少音频解码器），应换下一个候选内核
  bool fallbackSuggested;
}

/// Dart 调用原生。所有带 playerId 的方法作用于 [create] 返回的实例
@HostApi()
abstract class NativePlayerHostApi {
  NativeCapabilities capabilities();

  /// 字幕渲染使用的字体（Flutter 资源名），在 [create] 之前调用；
  /// 第一个作为默认字体，ASS 请求的字体找不到时回退到它
  void configureSubtitleFonts(List<String> assetKeys);

  int create();

  @async
  void open(int playerId, NativeSource source, bool autoPlay);

  void play(int playerId);

  void pause(int playerId);

  void playOrPause(int playerId);

  @async
  void seek(int playerId, int positionMs);

  void setRate(int playerId, double rate);

  /// 1.0 = 100%
  void setVolume(int playerId, double volume);

  void selectAudioTrack(int playerId, String trackId);

  /// trackId 为 null 时关闭字幕
  void selectSubtitleTrack(int playerId, String? trackId);

  /// 加载并选中外挂字幕；formatHint 为文件扩展名（如 srt、ass）
  @async
  void addExternalSubtitle(
    int playerId,
    String text,
    String title,
    String? formatHint,
  );

  void setVideoFit(int playerId, NativeVideoFit fit);

  NativeDiagnostics diagnostics(int playerId);

  void dispose(int playerId);
}

/// 原生回调 Dart，按 playerId 分发到对应引擎
@FlutterApi()
abstract class NativePlayerEventsApi {
  void onPosition(int playerId, int positionMs);

  void onDuration(int playerId, int durationMs);

  void onPlaying(int playerId, bool playing);

  void onBuffering(int playerId, bool buffering);

  void onCompleted(int playerId, bool completed);

  /// 每次 open 后第一帧画面上屏时调用一次（后台重建、seek 不再调用）
  void onFirstFrame(int playerId);

  void onRate(int playerId, double rate);

  void onVolume(int playerId, double volume);

  void onTracks(
    int playerId,
    List<NativeTrack> audio,
    List<NativeTrack> subtitle,
  );

  /// subtitleTrackId 为 null 且 subtitleOff 为 false 时表示由引擎自动选择
  void onSelectedTracks(
    int playerId,
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleOff,
  );

  void onVideoInfo(int playerId, NativeVideoInfo info);

  void onError(int playerId, NativeError error);
}
