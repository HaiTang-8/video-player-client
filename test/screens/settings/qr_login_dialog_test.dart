
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/core/localization/shadcn_zh_localizations.dart';
import 'package:media_player/core/theme/app_theme.dart';
import 'package:media_player/data/models/models.dart';
import 'package:media_player/data/services/api_client.dart';
import 'package:media_player/data/services/storage_service.dart';
import 'package:media_player/providers/providers.dart';
import 'package:media_player/screens/settings/driver_fields_form.dart';
import 'package:media_player/screens/settings/qr_login_dialog.dart';
import 'package:media_player/screens/settings/storage_form_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

// 1x1 透明 PNG
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _quark = DriverMeta(
  type: 'quark',
  label: '夸克网盘',
  fields: [
    FieldSpec(
      key: 'cookie',
      label: 'Cookie',
      kind: FieldKind.textarea,
      required: true,
    ),
    FieldSpec(key: 'root_fid', label: '根目录 fid', defaultValue: '0'),
    FieldSpec(
      key: 'link_delivery',
      label: '播放方式',
      kind: FieldKind.select,
      defaultValue: 'client',
      options: [
        FieldOption(value: 'client', label: '客户端直连'),
        FieldOption(value: 'server', label: '服务端代理'),
      ],
    ),
  ],
  capabilities: DriverCaps(qrLogin: true),
);

QrLoginChallenge _challenge(
  String id, {
  Duration ttl = const Duration(minutes: 3),
}) => QrLoginChallenge(
  sessionId: id,
  png: _png,
  url: 'https://qr.example/?token=$id',
  deadline: DateTime.now().add(ttl),
);

/// 按顺序返回状态；元素为 Exception 时抛出
class _Script {
  final List<Object> polls;
  final List<String> pollIds = [];
  int starts = 0;
  Object? startError;
  Duration ttl = const Duration(minutes: 3);

  _Script(this.polls);

  Future<QrLoginChallenge> start() async {
    starts++;
    if (startError != null) throw startError!;
    return _challenge('s$starts', ttl: ttl);
  }

  Future<QrLoginStatus> poll(String id) async {
    pollIds.add(id);
    final next = polls.length > 1 ? polls.removeAt(0) : polls.first;
    if (next is Exception) throw next;
    return next as QrLoginStatus;
  }
}

Widget _dialogHost(
  _Script script,
  ValueChanged<Map<String, String>?> onResult,
) {
  return shadcn.ShadcnApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.shadcnLightTheme,
    materialTheme: AppTheme.lightTheme,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      ShadcnZhLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ProviderScope(
      child: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    onResult(
                      await showQrLoginDialog(
                        context,
                        title: '扫码登录夸克网盘',
                        appName: '夸克 App',
                        start: script.start,
                        poll: script.poll,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
}

class _FakeStorageService extends StorageService {
  final _Script script;

  _FakeStorageService(this.script)
    : super(ApiClient(baseUrl: 'http://localhost:1'));

  @override
  Future<ApiResponse<QrLoginChallenge>> startQrLogin(String type) async =>
      ApiResponse(success: true, data: await script.start());

  @override
  Future<ApiResponse<QrLoginStatus>> pollQrLogin(
    String type,
    String sessionId,
  ) async => ApiResponse(success: true, data: await script.poll(sessionId));
}

const _pending = QrLoginStatus(state: QrLoginState.pending);
const _confirmed = QrLoginStatus(
  state: QrLoginState.confirmed,
  settings: {'cookie': '__pus=good; __puus=new'},
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump();
}

void main() {
  test('QrLoginChallenge converts expires_in to a local deadline', () {
    final c = QrLoginChallenge.fromJson({
      'session_id': 'a',
      'qr_png': 'iVBORw0KGgo=',
      'qr_url': 'https://qr.example',
      'expires_at': '2000-01-01T00:00:00Z',
      'expires_in': 120,
    });
    final left = c.deadline.difference(DateTime.now()).inSeconds;
    expect(left, inInclusiveRange(118, 120));
    expect(c.png.sublist(1, 4), 'PNG'.codeUnits);
    expect(
      QrLoginStatus.fromJson({'status': 'weird'}).state,
      QrLoginState.pending,
    );
    expect(
      QrLoginStatus.fromJson({
        'status': 'confirmed',
        'settings': {'cookie': 'a=1'},
      }).settings,
      {'cookie': 'a=1'},
    );
  });

  test('DriverFieldsController.apply fills declared and undeclared keys', () {
    final c = DriverFieldsController(_quark, {'cookie': 'old'});
    addTearDown(c.dispose);
    var notified = 0;
    c.addListener(() => notified++);
    c.apply({'cookie': 'new', 'link_delivery': 'server', 'extra': 'x'});
    expect(c.textController('cookie').text, 'new');
    expect(c.selectedValue('link_delivery'), 'server');
    expect(c.values()['extra'], 'x');
    c.apply({'link_delivery': 'bogus'});
    expect(c.selectedValue('link_delivery'), 'server');
    expect(notified, 2);
  });

  group('QrLoginDialog', () {
    testWidgets('polls until confirmed and returns the settings', (
      tester,
    ) async {
      final script = _Script([
        _pending,
        const QrLoginStatus(state: QrLoginState.scanned),
        _confirmed,
      ]);
      Map<String, String>? result;
      await tester.pumpWidget(_dialogHost(script, (r) => result = r));
      await _open(tester);
      expect(find.byKey(const ValueKey('qr-login-image')), findsOneWidget);
      expect(find.textContaining('请使用夸克 App 扫码登录'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已扫码，请在手机上确认登录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(result, {'cookie': '__pus=good; __puus=new'});
      expect(script.pollIds, ['s1', 's1', 's1']);
      expect(find.byType(QrLoginDialog), findsNothing);
    });

    testWidgets('server expiry offers a new code', (tester) async {
      final script = _Script([
        const QrLoginStatus(state: QrLoginState.expired),
        _pending,
      ]);
      await tester.pumpWidget(_dialogHost(script, (_) {}));
      await _open(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('二维码已过期'), findsOneWidget);
      expect(find.text('复制链接'), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      expect(script.pollIds, hasLength(1));

      await tester.tap(find.text('重新获取'));
      await tester.pump();
      await tester.pump();
      expect(script.starts, 2);
      expect(find.textContaining('请使用夸克 App 扫码登录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(script.pollIds.last, 's2');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('local deadline expires without waiting for the server', (
      tester,
    ) async {
      final script = _Script([_pending])..ttl = Duration.zero;
      await tester.pumpWidget(_dialogHost(script, (_) {}));
      await _open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('二维码已过期'), findsOneWidget);
      expect(script.pollIds, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('start failure shows the error and retries', (tester) async {
      final script = _Script([_pending])
        ..startError = const QrLoginException('网络不可用');
      await tester.pumpWidget(_dialogHost(script, (_) {}));
      await _open(tester);
      expect(find.text('获取二维码失败：网络不可用'), findsOneWidget);
      script.startError = null;
      await tester.tap(find.text('重新获取'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('qr-login-image')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('three poll failures in a row stop polling', (tester) async {
      final script = _Script([
        _pending,
        const QrLoginException('x'),
        const QrLoginException('x'),
        const QrLoginException('Cookie 校验失败'),
      ]);
      await tester.pumpWidget(_dialogHost(script, (_) {}));
      await _open(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(find.text('Cookie 校验失败'), findsOneWidget);
      expect(find.text('重新获取'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(script.pollIds, hasLength(4));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('copy link puts the qr url on the clipboard', (tester) async {
      final script = _Script([_pending]);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_dialogHost(script, (_) {}));
      await _open(tester);
      await tester.tap(find.text('复制链接'));
      await tester.pump();
      expect(copied, 'https://qr.example/?token=s1');
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('dark mode keeps the code on a white background', (
      tester,
    ) async {
      final script = _Script([_pending]);
      await tester.pumpWidget(
        shadcn.ShadcnApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.shadcnDarkTheme,
          materialTheme: AppTheme.darkTheme,
          home: Scaffold(
            body: QrLoginDialog(
              title: 't',
              appName: '夸克 App',
              start: script.start,
              poll: script.poll,
            ),
          ),
        ),
      );
      await tester.pump();
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('qr-login-image')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(box.color, Colors.white);
    });
  });

  testWidgets('storage form fills the cookie after QR login', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final script = _Script([_confirmed]);
    final router = GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/form',
          builder: (context, state) => const StorageFormScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageDriversProvider.overrideWith((ref) async => [_quark]),
          storageServiceProvider.overrideWithValue(_FakeStorageService(script)),
        ],
        child: shadcn.ShadcnApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.shadcnLightTheme,
          materialTheme: AppTheme.lightTheme,
          routerConfig: router,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            ShadcnZhLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('扫码登录'), findsNothing);
    await tester.tap(find.text('夸克网盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫码登录'));
    await tester.pump();
    await tester.pump();
    expect(find.text('扫码登录夸克网盘'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(QrLoginDialog), findsNothing);
    expect(find.text('__pus=good; __puus=new'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
