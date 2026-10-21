import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_player/native_player.dart';

/// 在真实宿主上验证 Dart 与原生插件之间的 Pigeon 通道和 PlatformView 注册
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host api round trip and video view mount', (tester) async {
    final api = NativePlayerHostApi();
    final caps = await api.capabilities();
    expect(caps.maxVolume, greaterThan(0));

    final id = await api.create();
    await expectLater(
      api.open(
        id,
        NativeSource(
          url: 'file:///nonexistent.mkv',
          httpHeaders: {},
          isLocalFile: true,
        ),
        true,
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'unsupported'),
      ),
    );
    expect(await api.diagnostics(id), isEmpty);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NativeVideoView(
          playerId: id,
          fit: NativeVideoFit.contain,
          onFitChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());

    await api.dispose(id);
    await expectLater(
      api.play(id),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'unknown_player',
        ),
      ),
    );
  });
}
