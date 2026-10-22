import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/range_test_server.dart';

void main() {
  late Directory dir;
  late File file;
  late RangeTestServer server;
  late HttpClient client;
  final bytes = Uint8List.fromList(List.generate(300 * 1024, (i) => i % 251));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('range_server_test');
    file = File('${dir.path}/sample.mkv')..writeAsBytesSync(bytes);
    server = await RangeTestServer.start(file);
    // 开发机上的 HTTP_PROXY 环境变量不排除本机地址
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await dir.delete(recursive: true);
  });

  Future<(HttpClientResponse, List<int>)> get(
    Uri uri, {
    String? range,
    String method = 'GET',
    bool followRedirects = true,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = followRedirects;
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (response, body);
  }

  test('serves the whole file without a range', () async {
    final (response, body) = await get(server.mediaUri);
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(body, bytes);
  });

  test('serves closed, open-ended and suffix ranges', () async {
    var (response, body) = await get(server.mediaUri, range: 'bytes=10-19');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 10-19/${bytes.length}',
    );
    expect(body, bytes.sublist(10, 20));

    (response, body) = await get(server.mediaUri, range: 'bytes=200000-');
    expect(body, bytes.sublist(200000));

    (response, body) = await get(server.mediaUri, range: 'bytes=-100');
    expect(body, bytes.sublist(bytes.length - 100));
  });

  test('rejects ranges beyond the end', () async {
    final (response, _) = await get(
      server.mediaUri,
      range: 'bytes=${bytes.length}-',
    );
    expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes */${bytes.length}',
    );
  });

  test('HEAD reports the length without a body', () async {
    final (response, body) = await get(server.mediaUri, method: 'HEAD');
    expect(response.contentLength, bytes.length);
    expect(response.headers.value(HttpHeaders.etagHeader), isNotNull);
    expect(body, isEmpty);
  });

  test('redirects to a signed media url', () async {
    final (response, _) = await get(
      server.redirectUri,
      method: 'HEAD',
      followRedirects: false,
    );
    expect(response.statusCode, HttpStatus.found);
    expect(
      response.headers.value(HttpHeaders.locationHeader),
      startsWith('/media/sample.mkv?sig='),
    );

    final (followed, body) = await get(server.redirectUri, range: 'bytes=0-9');
    expect(followed.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 10));
  });

  test('applies first byte latency and throttling', () async {
    server
      ..firstByteLatency = const Duration(milliseconds: 150)
      ..bytesPerSecond = 1024 * 1024;
    final watch = Stopwatch()..start();
    final (_, body) = await get(server.mediaUri, range: 'bytes=0-262143');
    expect(body.length, 256 * 1024);
    // 150ms 延迟 + 256KiB / 1MiB/s ≈ 250ms，后一个 64KiB 分块之后才开始等待
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(330));
  });

  test('answers 500 instead of hanging when the file is gone', () async {
    await file.delete();
    final (response, _) = await get(server.mediaUri, method: 'HEAD');
    expect(response.statusCode, HttpStatus.internalServerError);
  });

  test('records request statistics', () async {
    await get(server.mediaUri, range: 'bytes=0-99');
    await get(server.mediaUri, method: 'HEAD');
    expect(server.requestCount, 2);
    expect(server.bytesServed, 100);
    expect(server.requestLog, [
      'GET /media/sample.mkv bytes=0-99',
      'HEAD /media/sample.mkv -',
    ]);
    server.resetStats();
    expect(server.requestCount, 0);
  });

  test('parseRange handles edge cases', () {
    expect(RangeTestServer.parseRange('bytes=0-', 10), (0, 9));
    expect(RangeTestServer.parseRange('bytes=5-100', 10), (5, 9));
    expect(RangeTestServer.parseRange('bytes=-20', 10), (0, 9));
    expect(RangeTestServer.parseRange('bytes=9-3', 10), isNull);
    expect(RangeTestServer.parseRange('bytes=0-1,4-5', 10), isNull);
    expect(RangeTestServer.parseRange('items=0-1', 10), isNull);
  });
}
