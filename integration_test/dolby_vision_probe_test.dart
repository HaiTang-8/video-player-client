import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_player/native_player.dart';

/// 杜比视界 GPU 重建的手动诊断：在真机上播放 DOVI_PROBE_URL，停在 DOVI_PROBE_SEEK_MS 附近
/// DOVI_PROBE_HOLD_S 秒，期间打印 DOVI_HOLD 标记，供 adb 截图、dumpsys 和 logcat 观察。
/// 配合调试属性（见 `DoviSupport`）可以读回 PQ 网格或输出帧统计。不要用 `flutter test` 运行，
/// 它结束时会卸载 App；用 `flutter build apk -t` 构建后 `adb install -r` 安装再启动
const _url = String.fromEnvironment('DOVI_PROBE_URL');
const _seekMs = int.fromEnvironment('DOVI_PROBE_SEEK_MS');
const _holdSeconds = int.fromEnvironment('DOVI_PROBE_HOLD_S', defaultValue: 20);
const _pause = bool.fromEnvironment('DOVI_PROBE_PAUSE');

/// 保持期间每 3 秒依次跳转到这些位置（毫秒，逗号分隔），验证 seek 后元数据对齐
const _seeks = String.fromEnvironment('DOVI_PROBE_SEEKS');

/// 大于 0 时，播放位置超过该值（毫秒）就跳回开头，用于长时间连续播放
const _loopMs = int.fromEnvironment('DOVI_PROBE_LOOP_MS');

/// 非空时保持结束后在同一个播放器里打开这个地址，再保持 DOVI_PROBE_HOLD_S 秒（验证换片后切回直出）
const _nextUrl = String.fromEnvironment('DOVI_PROBE_NEXT_URL');

class _Events implements NativePlayerEventsApi {
  int positionMs = 0;
  bool playing = false;
  NativeVideoInfo? videoInfo;
  final errors = <NativeError>[];

  @override
  void onPosition(int playerId, int positionMs) => this.positionMs = positionMs;
  @override
  void onDuration(int playerId, int durationMs) {}
  @override
  void onBufferedPosition(int playerId, int bufferedMs) {}
  @override
  void onPlaying(int playerId, bool playing) => this.playing = playing;
  @override
  void onBuffering(int playerId, bool buffering) {}
  @override
  void onCompleted(int playerId, bool completed) {}
  @override
  void onFirstFrame(int playerId) {}
  @override
  void onRate(int playerId, double rate) {}
  @override
  void onVolume(int playerId, double volume) {}
  @override
  void onTracks(
    int playerId,
    List<NativeTrack> audio,
    List<NativeTrack> subtitle,
  ) {}
  @override
  void onSelectedTracks(
    int playerId,
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleOff,
  ) {}
  @override
  void onVideoInfo(int playerId, NativeVideoInfo info) => videoInfo = info;
  @override
  void onError(int playerId, NativeError error) => errors.add(error);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dolby vision probe playback', (tester) async {
    final api = NativePlayerHostApi();
    final events = _Events();
    final id = await api.create();
    NativePlayerEventDispatcher.instance.register(id, events);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NativeVideoView(
          playerId: id,
          fit: NativeVideoFit.contain,
          onFitChanged: (fit) => api.setVideoFit(id, fit),
        ),
      ),
    );
    await api.open(
      id,
      NativeSource(url: _url, httpHeaders: const {}, isLocalFile: false),
      true,
    );
    for (var i = 0; i < 300 && !events.playing; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (_pause) await api.pause(id);
    if (_seekMs > 0) await api.seek(id, _seekMs);
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint(
      'DOVI_HOLD start info=${events.videoInfo?.dynamicRange} errors=${events.errors.map((e) => e.message)}',
    );
    final seeks =
        _seeks.isEmpty ? <int>[] : _seeks.split(',').map(int.parse).toList();
    for (var i = 0; i < _holdSeconds * 10; i++) {
      if (_loopMs > 0 && events.positionMs > _loopMs) {
        events.positionMs = 0;
        await api.seek(id, 0);
      }
      if (seeks.isNotEmpty && i > 0 && i % 30 == 0) {
        await api.seek(id, seeks[(i ~/ 30 - 1) % seeks.length]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    if (_nextUrl.isNotEmpty) {
      await api.open(
        id,
        NativeSource(url: _nextUrl, httpHeaders: const {}, isLocalFile: false),
        true,
      );
      debugPrint('DOVI_HOLD next');
      for (var i = 0; i < _holdSeconds * 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }
    debugPrint(
      'DOVI_HOLD end position=${events.positionMs} diag=${await api.diagnostics(id)}',
    );
    await tester.pumpWidget(const SizedBox());
    NativePlayerEventDispatcher.instance.unregister(id);
    await api.dispose(id);
  }, skip: _url.isEmpty);
}
