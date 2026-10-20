import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/mpv/mpv_error_mapper.dart';

void main() {
  test('ignores empty error', () {
    expect(MpvErrorMapper.map(''), isNull);
  });

  test('audio device error is recoverable audio output error', () {
    final error = MpvErrorMapper.map('Could not open/initialize audio device');
    expect(error!.kind, PlaybackErrorKind.audioOutput);
    expect(error.recoverable, isTrue);
  });

  test('network errors are recoverable', () {
    const messages = [
      'ffurl_write failed',
      'ffurl_read returned error',
      'tcp: Connection refused',
      'tcp: Connection reset by peer',
      'tcp: Connection timed out',
      'Connection refused',
      'Connection reset',
      'connection timed out',
      'Network is unreachable',
      'End of file',
    ];
    for (final message in messages) {
      final error = MpvErrorMapper.map(message);
      expect(error!.kind, PlaybackErrorKind.network, reason: message);
      expect(error.recoverable, isTrue, reason: message);
    }
  });

  test('http 5xx is recoverable, 4xx is not', () {
    final server = MpvErrorMapper.map('HTTP error 503 Service Unavailable');
    expect(server!.kind, PlaybackErrorKind.http);
    expect(server.httpStatus, 503);
    expect(server.recoverable, isTrue);

    final returned = MpvErrorMapper.map('Server returned 502 Bad Gateway');
    expect(returned!.recoverable, isTrue);

    final notFound = MpvErrorMapper.map('HTTP error 404 Not Found');
    expect(notFound!.httpStatus, 404);
    expect(notFound.recoverable, isFalse);
  });

  test('status code without http context is not treated as http error', () {
    final error = MpvErrorMapper.map('Failed to open stream 500');
    expect(error!.kind, PlaybackErrorKind.unknown);
    expect(error.recoverable, isFalse);
  });
}
