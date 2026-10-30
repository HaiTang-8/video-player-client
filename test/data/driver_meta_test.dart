import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/driver_meta.dart';

void main() {
  test('parses the quark declaration with null stream_modes', () {
    final meta = DriverMeta.fromJson({
      'type': 'quark',
      'label': '夸克网盘',
      'fields': [
        {
          'key': 'cookie',
          'label': 'Cookie',
          'kind': 'textarea',
          'required': true,
          'rotating': true,
          'help': '从浏览器复制',
        },
        {
          'key': 'link_delivery',
          'label': '播放方式',
          'kind': 'select',
          'default': 'client',
          'options': [
            {'value': 'client', 'label': '客户端直连'},
            {'value': 'server', 'label': '服务端代理'},
          ],
        },
        {'key': 'max_connections', 'label': '并发连接数', 'kind': 'number'},
        {'key': 'future', 'kind': 'color'},
      ],
      'capabilities': {
        'direct_link': true,
        'variants': true,
        'stream_modes': null,
        'qr_login': false,
      },
    });

    expect(meta.type, 'quark');
    expect(meta.fields.map((f) => f.kind), [
      FieldKind.textarea,
      FieldKind.select,
      FieldKind.number,
      FieldKind.text,
    ]);
    final cookie = meta.fields.first;
    expect(cookie.required, isTrue);
    expect(cookie.rotating, isTrue);
    expect(cookie.help, '从浏览器复制');
    expect(cookie.placeholder, isNull);
    expect(meta.fields[1].defaultValue, 'client');
    expect(meta.fields[1].options.map((o) => o.label), ['客户端直连', '服务端代理']);
    expect(meta.fields[3].label, 'future');
    expect(meta.capabilities.directLink, isTrue);
    expect(meta.capabilities.streamModes, isEmpty);
  });

  test('tolerates missing fields and capabilities', () {
    final meta = DriverMeta.fromJson({'type': 'x'});
    expect(meta.label, 'x');
    expect(meta.fields, isEmpty);
    expect(meta.capabilities.streamModes, isEmpty);
  });

  test('find matches the type case-insensitively', () {
    const metas = [
      DriverMeta(type: 'quark', label: '夸克网盘'),
      DriverMeta(type: 'other', label: 'Other'),
    ];
    expect(DriverMeta.find(metas, ' QUARK ')?.label, '夸克网盘');
    expect(DriverMeta.find(metas, 'webdav'), isNull);
  });
}
