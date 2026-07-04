import 'package:dio/dio.dart';

import 'proxy_http_client_adapter_stub.dart'
    if (dart.library.io) 'proxy_http_client_adapter_io.dart'
    as impl;

void configureDioProxy(Dio dio, String? proxyUrl) {
  impl.configureDioProxy(dio, proxyUrl);
}
