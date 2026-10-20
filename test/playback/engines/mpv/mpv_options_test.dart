import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/engines/mpv/mpv_options.dart';

void main() {
  test('streaming presets keep the original property order', () {
    final options = MpvOptions().networkResilience().streamCache().build();
    expect(options.keys, [
      'stream-lavf-o',
      'network-timeout',
      'cache',
      'demuxer-max-back-bytes',
      'cache-secs',
      'cache-pause',
      'cache-pause-wait',
    ]);
    expect(options['network-timeout'], '30');
    expect(options['stream-lavf-o'], contains('reconnect_on_http_error=5xx'));
  });
}
