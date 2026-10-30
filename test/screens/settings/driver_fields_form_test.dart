import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/core/localization/shadcn_zh_localizations.dart';
import 'package:media_player/core/theme/app_theme.dart';
import 'package:media_player/core/widgets/form_page.dart';
import 'package:media_player/core/widgets/password_text_field.dart';
import 'package:media_player/data/models/models.dart';
import 'package:media_player/providers/providers.dart';
import 'package:media_player/screens/settings/driver_fields_form.dart';
import 'package:media_player/screens/settings/storage_form_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _quark = DriverMeta(
  type: 'quark',
  label: '夸克网盘',
  fields: [
    FieldSpec(
      key: 'cookie',
      label: 'Cookie',
      kind: FieldKind.textarea,
      required: true,
      rotating: true,
      help: '从浏览器复制 Cookie',
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
    FieldSpec(
      key: 'max_connections',
      label: '并发连接数',
      kind: FieldKind.number,
      defaultValue: '16',
    ),
  ],
  capabilities: DriverCaps(directLink: true),
);

const _allKinds = DriverMeta(
  type: 'all',
  label: 'All',
  fields: [
    FieldSpec(key: 'text', label: 'Text'),
    FieldSpec(key: 'password', label: 'Password', kind: FieldKind.password),
    FieldSpec(key: 'url', label: 'Url', kind: FieldKind.url),
    FieldSpec(
      key: 'many',
      label: 'Many',
      kind: FieldKind.select,
      options: [
        FieldOption(value: 'a', label: 'A'),
        FieldOption(value: 'b', label: 'B'),
        FieldOption(value: 'c', label: 'C'),
        FieldOption(value: 'd', label: 'D'),
      ],
    ),
  ],
);

Widget _app(Widget child, {bool dark = false}) {
  return shadcn.ShadcnApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.shadcnLightTheme,
    darkTheme: AppTheme.shadcnDarkTheme,
    themeMode: dark ? shadcn.ThemeMode.dark : shadcn.ThemeMode.light,
    materialTheme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      ShadcnZhLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Widget _formApp(
  Future<List<DriverMeta>> Function() drivers, {
  Storage? storage,
}) {
  final router = GoRouter(
    initialLocation: '/form',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      GoRoute(
        path: '/form',
        builder:
            (context, state) => StorageFormScreen(
              storageId: storage?.id,
              storage: storage,
            ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [storageDriversProvider.overrideWith((ref) => drivers())],
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
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

bool _submitEnabled(WidgetTester tester, String label) =>
    tester
        .widget<shadcn.Button>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(shadcn.Button),
          ),
        )
        .onPressed !=
    null;

void main() {
  group('DriverFieldsController', () {
    test('fills defaults and keeps saved and undeclared values', () {
      final c = DriverFieldsController(_quark, {
        'cookie': 'a=1; b=2',
        'link_delivery': 'server',
        'legacy': 'keep',
      });
      addTearDown(c.dispose);
      expect(c.textController('root_fid').text, '0');
      expect(c.selectedValue('link_delivery'), 'server');
      expect(c.values(), {
        'cookie': 'a=1; b=2',
        'root_fid': '0',
        'link_delivery': 'server',
        'max_connections': '16',
        'legacy': 'keep',
      });
    });

    test('invalid saved select value falls back to the default', () {
      final c = DriverFieldsController(_quark, {'link_delivery': 'gone'});
      addTearDown(c.dispose);
      expect(c.selectedValue('link_delivery'), 'client');
    });

    test('omits empty values, trims text but not passwords', () {
      final c = DriverFieldsController(_allKinds);
      addTearDown(c.dispose);
      c.textController('text').text = '  hi  ';
      c.textController('password').text = ' p ';
      expect(c.selectedValue('many'), isNull);
      expect(c.values(), {'text': 'hi', 'password': ' p '});
      c.select('many', 'c');
      expect(c.values()['many'], 'c');
    });

    test('validate reports required and number errors', () {
      final c = DriverFieldsController(_quark);
      addTearDown(c.dispose);
      expect(c.validate(), '请填写Cookie');
      c.textController('cookie').text = '   ';
      expect(c.validate(), '请填写Cookie');
      c.textController('cookie').text = 'a=1';
      c.textController('max_connections').text = '1x';
      expect(c.validate(), '并发连接数必须是整数');
      c.textController('max_connections').clear();
      expect(c.validate(), isNull);
      expect(c.values().containsKey('max_connections'), isFalse);
    });
  });

  group('DriverFieldsForm', () {
    testWidgets('renders each kind with label, help and a multi-line cookie', (
      tester,
    ) async {
      _phone(tester);
      final c = DriverFieldsController(_quark, {'cookie': 'k=${'x' * 3000}'});
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(DriverFieldsForm(controller: c)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cookie'), findsOneWidget);
      expect(find.text('从浏览器复制 Cookie'), findsOneWidget);
      final cookie = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('driver-field-cookie')),
          matching: find.byType(EditableText),
        ),
      );
      expect(cookie.minLines, 3);
      expect(cookie.maxLines, 5);
      expect(
        tester.getSize(find.byKey(const ValueKey('driver-field-cookie'))).width,
        lessThanOrEqualTo(390),
      );
      final number = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('driver-field-max_connections')),
          matching: find.byType(EditableText),
        ),
      );
      expect(number.keyboardType, TextInputType.number);

      expect(find.byType(FormOptionCard), findsNWidgets(2));
      await tester.tap(find.text('服务端代理'));
      await tester.pump();
      expect(c.selectedValue('link_delivery'), 'server');
    });

    testWidgets('uses PasswordTextField and a Select for many options', (
      tester,
    ) async {
      final c = DriverFieldsController(_allKinds);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(DriverFieldsForm(controller: c), dark: true));
      await tester.pumpAndSettle();
      expect(find.byType(PasswordTextField), findsOneWidget);
      expect(find.byType(shadcn.Select<String>), findsOneWidget);
      expect(find.byType(FormOptionCard), findsNothing);
    });
  });

  group('StorageFormScreen with declared drivers', () {
    testWidgets('quark shows declared fields and hides stream mode', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_formApp(() async => [_quark]));
      await tester.pumpAndSettle();
      expect(find.text('流媒体模式'), findsOneWidget);

      await tester.tap(find.text('夸克网盘'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);
      expect(find.text('流媒体模式'), findsNothing);
      expect(find.text('WebDAV URL'), findsNothing);
      expect(_submitEnabled(tester, '添加'), isTrue);
    });

    testWidgets('wide window keeps the type cards on one row', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_formApp(() async => [_quark]));
      await tester.pumpAndSettle();
      final rows = {
        for (final label in ['WebDAV', '本地存储', 'OpenList', '夸克网盘'])
          tester.getCenter(find.text(label)).dy,
      };
      expect(rows, hasLength(1));

      tester.view.physicalSize = const Size(320 * 3, 1800 * 3);
      tester.view.devicePixelRatio = 3;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.text('OpenList')).dy,
        greaterThan(tester.getCenter(find.text('WebDAV')).dy),
      );
    });

    testWidgets('loading keeps save disabled', (tester) async {
      _phone(tester);
      final pending = Completer<List<DriverMeta>>();
      await tester.pumpWidget(_formApp(() => pending.future));
      await tester.pumpAndSettle();
      await tester.tap(find.text('夸克网盘'));
      await tester.pump();
      expect(find.text('Cookie'), findsNothing);
      expect(_submitEnabled(tester, '添加'), isFalse);
    });

    testWidgets('load failure shows the error and retries', (tester) async {
      _phone(tester);
      var calls = 0;
      await tester.pumpWidget(
        _formApp(() async {
          calls++;
          if (calls == 1) throw 'boom';
          return [_quark];
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('夸克网盘'));
      await tester.pumpAndSettle();
      expect(find.textContaining('加载配置项失败'), findsOneWidget);
      expect(_submitEnabled(tester, '添加'), isFalse);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Cookie'), findsOneWidget);
    });

    testWidgets('server without the declaration blocks saving', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_formApp(() async => const []));
      await tester.pumpAndSettle();
      await tester.tap(find.text('夸克网盘'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请升级服务端'), findsOneWidget);
      expect(_submitEnabled(tester, '添加'), isFalse);
    });

    testWidgets('editing quark loads the saved cookie', (tester) async {
      _phone(tester);
      final storage = Storage(
        id: 7,
        name: '夸克',
        type: 'quark',
        enabled: true,
        settings: const {'cookie': 'saved=1', 'root_fid': 'abc'},
      );
      await tester.pumpWidget(
        _formApp(() async => [_quark], storage: storage),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved=1'), findsOneWidget);
      expect(find.text('abc'), findsOneWidget);
      expect(_submitEnabled(tester, '保存'), isTrue);
    });

    testWidgets('unknown type is read-only instead of webdav', (tester) async {
      _phone(tester);
      final storage = Storage(
        id: 8,
        name: '未来网盘',
        type: 'baidu',
        enabled: true,
        settings: const {'token': 't'},
      );
      await tester.pumpWidget(
        _formApp(() async => [_quark], storage: storage),
      );
      await tester.pumpAndSettle();
      expect(find.text('baidu'), findsOneWidget);
      expect(find.text('WebDAV URL'), findsNothing);
      expect(find.text('夸克网盘'), findsNothing);
      expect(find.textContaining('不支持类型「baidu」'), findsOneWidget);
      expect(_submitEnabled(tester, '保存'), isFalse);
    });

    testWidgets('unknown type declared by the server uses its fields', (
      tester,
    ) async {
      _phone(tester);
      final storage = Storage(
        id: 9,
        name: '未来网盘',
        type: 'baidu',
        enabled: true,
        settings: const {'token': 't'},
      );
      const baidu = DriverMeta(
        type: 'baidu',
        label: '百度网盘',
        fields: [
          FieldSpec(key: 'token', label: 'Token', kind: FieldKind.password),
        ],
      );
      await tester.pumpWidget(
        _formApp(() async => [baidu], storage: storage),
      );
      await tester.pumpAndSettle();
      expect(find.text('Token'), findsOneWidget);
      expect(_submitEnabled(tester, '保存'), isTrue);
    });
  });
}
