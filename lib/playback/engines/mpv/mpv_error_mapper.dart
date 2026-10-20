import '../../domain/playback_domain.dart';

/// 把 media_kit 上报的 mpv 错误文本映射为 [PlaybackError]
abstract final class MpvErrorMapper {
  static const _networkPatterns = [
    'ffurl_write',
    'ffurl_read',
    'tcp: connection refused',
    'tcp: connection reset',
    'tcp: connection timed out',
    'connection refused',
    'connection reset',
    'connection timed out',
    'network is unreachable',
    'end of file',
  ];

  static PlaybackError? map(String error) {
    if (error.isEmpty) return null;
    if (error.contains('Could not open/initialize audio device')) {
      return PlaybackError(
        kind: PlaybackErrorKind.audioOutput,
        message: error,
        recoverable: true,
      );
    }
    final message = error.toLowerCase();
    if (_networkPatterns.any(message.contains)) {
      return PlaybackError(
        kind: PlaybackErrorKind.network,
        message: error,
        recoverable: true,
      );
    }
    final httpStatus = _httpStatus(message);
    if (httpStatus != null) {
      return PlaybackError(
        kind: PlaybackErrorKind.http,
        message: error,
        httpStatus: httpStatus,
        recoverable: httpStatus >= 500 && httpStatus <= 599,
      );
    }
    return PlaybackError(kind: PlaybackErrorKind.unknown, message: error);
  }

  static int? _httpStatus(String message) {
    if (!message.contains('http error') &&
        !message.contains('server returned')) {
      return null;
    }
    final match = RegExp(r'\b([1-5]\d{2})\b').firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
