import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:socks5_proxy/socks_client.dart';

void configureDioProxy(Dio dio, String? proxyUrl) {
  final value = proxyUrl?.trim();
  if (value == null || value.isEmpty) return;

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority) return;
  if (!_isSupportedProxyScheme(uri.scheme)) return;

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      if (uri.scheme == 'socks5') {
        _configureSocks5Proxy(client, uri);
      } else {
        client.findProxy = (_) => 'PROXY ${_proxyAuthority(uri)}';
        final credentials = _proxyCredentials(uri);
        if (credentials != null) {
          client.authenticateProxy = (host, port, scheme, realm) async {
            client.addProxyCredentials(
              host,
              port,
              realm ?? '',
              HttpClientBasicCredentials(credentials.$1, credentials.$2),
            );
            return true;
          };
        }
      }
      return client;
    },
  );
}

bool _isSupportedProxyScheme(String scheme) {
  return scheme == 'http' || scheme == 'https' || scheme == 'socks5';
}

void _configureSocks5Proxy(HttpClient client, Uri proxy) {
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (url, _, _) async {
    final proxyAddress = await _resolveProxyAddress(proxy.host);
    final credentials = _proxyCredentials(proxy);
    final proxySettings = ProxySettings(
      proxyAddress,
      proxy.hasPort ? proxy.port : 1080,
      username: credentials?.$1,
      password: credentials?.$2,
    );
    final socksSocket = SocksTCPClient.connect(
      [proxySettings],
      InternetAddress(url.host, type: InternetAddressType.unix),
      url.port,
    );

    if (url.scheme == 'https') {
      final secureSocket = (await socksSocket).secure(url.host);
      return ConnectionTask.fromSocket(
        secureSocket,
        () async => (await secureSocket).close().ignore(),
      );
    }

    return ConnectionTask.fromSocket(
      socksSocket,
      () async => (await socksSocket).close().ignore(),
    );
  };
}

Future<InternetAddress> _resolveProxyAddress(String host) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) return parsed;
  final addresses = await InternetAddress.lookup(host);
  return addresses.first;
}

String _proxyAuthority(Uri uri) {
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final userInfo = uri.userInfo.isEmpty ? '' : '${uri.userInfo}@';
  return '$userInfo${uri.host}:$port';
}

(String, String)? _proxyCredentials(Uri uri) {
  if (uri.userInfo.isEmpty) return null;
  final separator = uri.userInfo.indexOf(':');
  final username =
      separator >= 0 ? uri.userInfo.substring(0, separator) : uri.userInfo;
  if (username.isEmpty) return null;
  final password = separator >= 0 ? uri.userInfo.substring(separator + 1) : '';
  return (Uri.decodeComponent(username), Uri.decodeComponent(password));
}
