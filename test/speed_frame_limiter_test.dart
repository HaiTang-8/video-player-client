import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/screens/player/speed_frame_limiter.dart';

double? target(double fps, double rate, double refresh) =>
    SpeedFrameLimiter.targetSourceFps(
      sourceFps: fps,
      rate: rate,
      refreshRate: refresh,
    );

void main() {
  test('no limit at normal or slow speed', () {
    expect(target(60, 1.0, 120), isNull);
    expect(target(60, 0.5, 120), isNull);
  });

  test('caps output to half refresh on high refresh displays', () {
    expect(target(60, 1.25, 120), 48);
    expect(target(60, 1.5, 120), 40);
    expect(target(60, 2.0, 120), 30);
  });

  test('caps output to refresh on 60Hz displays', () {
    expect(target(60, 1.25, 60), 48);
    expect(target(60, 2.0, 60), 30);
  });

  test('no limit when output already fits', () {
    expect(target(30, 2.0, 120), isNull);
    expect(target(24, 2.0, 60), isNull);
  });

  test('ignores unknown fps or refresh rate', () {
    expect(target(0, 2.0, 120), isNull);
    expect(target(60, 2.0, 0), isNull);
  });
}
