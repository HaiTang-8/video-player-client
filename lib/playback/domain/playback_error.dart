enum PlaybackErrorKind { network, http, audioOutput, source, decoder, unknown }

class PlaybackError {
  final PlaybackErrorKind kind;
  final String message;
  final int? httpStatus;

  /// 临时性错误，通常会自动恢复，不应中断播放
  final bool recoverable;

  const PlaybackError({
    required this.kind,
    required this.message,
    this.httpStatus,
    this.recoverable = false,
  });

  @override
  String toString() => message;
}
