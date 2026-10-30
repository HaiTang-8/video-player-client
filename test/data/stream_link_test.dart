import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/stream_info.dart';
import 'package:media_player/data/models/stream_link.dart';

void main() {
  test('parses a direct link response', () {
    final link = StreamLink.fromJson({
      'delivery': 'direct_link',
      'kind': 'hls',
      'variant': '4k',
      'url': 'https://cdn.example/a.m3u8',
      'headers': {'Cookie': '__puus=x'},
      'expires_at': '2026-11-01T00:55:54Z',
      'max_connections': 1,
    });
    expect(link.isDirect, isTrue);
    expect(link.kind, StreamLinkKind.hls);
    expect(link.variant, '4k');
    expect(link.headers, {'Cookie': '__puus=x'});
    expect(link.expiresAt, DateTime.utc(2026, 11, 1, 0, 55, 54));
    expect(link.maxConnections, 1);
  });

  test('an old server response is a stream link with defaults', () {
    final link = StreamLink.fromJson({'url': '/api/v1/stream/3/a.mkv'});
    expect(link.isDirect, isFalse);
    expect(link.kind, StreamLinkKind.file);
    expect(link.variant, StreamLink.originalVariant);
    expect(link.headers, isEmpty);
    expect(link.expiresAt, isNull);
    expect(link.maxConnections, isNull);
  });

  test('stream info carries delivery and source id', () {
    final info = StreamInfo.fromJson({
      'safe_url': '/api/v1/stream/source/9',
      'source_id': 9,
      'delivery': 'direct_link',
    });
    expect(info.sourceId, 9);
    expect(info.delivery, StreamDelivery.directLink);
    expect(StreamInfo.fromJson({'url': '/x'}).delivery, StreamDelivery.stream);
    expect(
      StreamInfo.fromJson(info.toJson()).delivery,
      StreamDelivery.directLink,
    );
  });

  test('variants parse the server list', () {
    final hd = LinkVariant.fromJson({
      'id': 'super',
      'label': '超清 转码',
      'kind': 'hls',
      'height': 1080,
      'original': false,
    });
    expect(hd.id, 'super');
    expect(hd.label, '超清 转码');
    expect(hd.kind, StreamLinkKind.hls);
    expect(hd.original, isFalse);

    final original = LinkVariant.fromJson({
      'id': 'original',
      'label': '原画',
      'kind': 'file',
      'original': true,
    });
    expect(original.kind, StreamLinkKind.file);
    expect(original.original, isTrue);
  });
}
