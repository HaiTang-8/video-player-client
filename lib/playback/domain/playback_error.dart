enum PlaybackErrorKind { network, http, audioOutput, source, decoder, unknown }

class PlaybackError {
  final PlaybackErrorKind kind;
  final String message;
  final int? httpStatus;

  /// 临时性错误，通常会自动恢复，不应中断播放
  final bool recoverable;

  /// 当前内核无法播放此媒体，会话应换下一个候选内核从原位置继续
  final bool fallbackSuggested;

  const PlaybackError({
    required this.kind,
    required this.message,
    this.httpStatus,
    this.recoverable = false,
    this.fallbackSuggested = false,
  });

  @override
  String toString() => message;
}
