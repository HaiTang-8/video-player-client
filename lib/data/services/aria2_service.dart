import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class Aria2Service {
  final String rpcUrl;
  final String? secret;
  final Dio _dio;

  Aria2Service({
    required this.rpcUrl,
    this.secret,
  }) : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ));

  Future<Map<String, dynamic>> _call(String method, [List<dynamic>? params]) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final body = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params ?? [],
    };

    if (secret != null && secret!.isNotEmpty) {
      body['params'] = ['token:$secret', ...(params ?? [])];
    }

    debugPrint('[Aria2] RPC call: $method');
    final response = await _dio.post(rpcUrl, data: jsonEncode(body));

    if (response.statusCode == 200) {
      final data = response.data is String ? jsonDecode(response.data) : response.data;
      if (data['error'] != null) {
        throw Exception('aria2 error: ${data['error']['message']}');
      }
      return data;
    }
    throw Exception('aria2 RPC failed: ${response.statusCode}');
  }

  Future<String> getVersion() async {
    final result = await _call('aria2.getVersion');
    return result['result']['version'] as String;
  }

  Future<void> shutdown({bool force = false}) async {
    await _call(force ? 'aria2.forceShutdown' : 'aria2.shutdown');
  }

  Future<String> addUri(
    String url, {
    String? dir,
    String? filename,
    Map<String, String>? headers,
  }) async {
    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;
    if (filename != null) options['out'] = filename;

    // 使用传入的 headers，如果没有 User-Agent 则使用默认值
    final allHeaders = <String>[];
    bool hasUserAgent = false;
    if (headers != null && headers.isNotEmpty) {
      for (final entry in headers.entries) {
        allHeaders.add('${entry.key}: ${entry.value}');
        if (entry.key.toLowerCase() == 'user-agent') {
          hasUserAgent = true;
        }
      }
    }
    // 如果没有传入 User-Agent，使用默认值（与 aria2 配置一致）
    if (!hasUserAgent) {
      allHeaders.insert(0, 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57');
    }
    options['header'] = allHeaders;

    debugPrint('[Aria2] Headers: $allHeaders');

    final result = await _call('aria2.addUri', [
      [url],
      options,
    ]);
    final gid = result['result'] as String;
    debugPrint('[Aria2] Task added, gid=$gid');
    return gid;
  }

  Future<Map<String, dynamic>> tellStatus(String gid) async {
    final result = await _call('aria2.tellStatus', [gid]);
    return result['result'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> tellActive() async {
    final result = await _call('aria2.tellActive');
    return (result['result'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> pause(String gid) async {
    await _call('aria2.pause', [gid]);
  }

  Future<void> unpause(String gid) async {
    await _call('aria2.unpause', [gid]);
  }

  Future<void> remove(String gid) async {
    await _call('aria2.remove', [gid]);
  }

  Future<Map<String, dynamic>> getGlobalStat() async {
    final result = await _call('aria2.getGlobalStat');
    return result['result'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> tellWaiting(int offset, int num) async {
    final result = await _call('aria2.tellWaiting', [offset, num]);
    return (result['result'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> tellStopped(int offset, int num) async {
    final result = await _call('aria2.tellStopped', [offset, num]);
    return (result['result'] as List).cast<Map<String, dynamic>>();
  }

  void dispose() {
    _dio.close();
  }
}
