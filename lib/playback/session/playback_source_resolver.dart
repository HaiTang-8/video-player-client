import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/utils/http_utils.dart';
import '../../data/models/subtitle_info.dart';
import '../../data/services/download_service.dart';
import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import 'playback_gateways.dart';
import 'playback_item.dart';

/// 片源一侧关心的播放事件（例如本机缓存代理据此记录封装头和续播点），由会话在对应时机调用
abstract interface class PlaybackSourceObserver {
  void onOpening(Duration? startAt);

  void onFirstFrame();

  /// 用户发起的 seek
  void onSeek(Duration position);

  void onProgress(Duration position, Duration duration);
}

class ResolvedPlayback {
  final PlaybackSource source;
  final int? storageId;

  /// 文件在存储源中的路径，用于媒体信息展示和查找外挂字幕
  final String? filePath;
  final PlaybackSourceObserver? observer;

  const ResolvedPlayback(
    this.source, {
    this.storageId,
    this.filePath,
    this.observer,
  });
}

class PlaybackSourceUnavailable implements Exception {
  const PlaybackSourceUnavailable();

  @override
  String toString() => '无法获取播放地址';
}

/// 解析播放地址：本地缓存优先，其次是服务端流地址（处理 302 跳转与鉴权头）
class PlaybackSourceResolver {
  PlaybackSourceResolver(this._gateway, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final PlaybackSourceGateway _gateway;
  final Dio _dio;

  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    final localPath = await _gateway.findDownloadedFile(item);
    if (localPath != null) {
      return ResolvedPlayback(PlaybackSource.localFile(localPath));
    }

    final info = await _gateway.fetchStreamInfo(item);
    final streamUrl = info?.url;
    if (info == null || streamUrl == null || streamUrl.isEmpty) {
      throw const PlaybackSourceUnavailable();
    }

    final fullUrl =
        streamUrl.startsWith('http')
            ? streamUrl
            : '${_gateway.serverUrl}$streamUrl';
    final authHeaders = await _authHeadersFor(fullUrl, info.storageId);
    final resolvedUrl = await _resolveRedirect(fullUrl, authHeaders);
    final playUrl = resolvedUrl ?? fullUrl;
    // 重定向后 URL 可能变更 origin，需要重新判断 auth
    final playHeaders =
        (resolvedUrl != null && resolvedUrl != fullUrl)
            ? await _authHeadersFor(playUrl, info.storageId)
            : authHeaders;
    return ResolvedPlayback(
      PlaybackSource.network(
        playUrl,
        httpHeaders: {
          'User-Agent': DownloadService.aria2UserAgent,
          ...?playHeaders,
        },
      ),
      storageId: info.storageId,
      filePath: info.filePath,
    );
  }

  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async {
    final localPath = subtitle.localPath;
    if (localPath != null) return File(localPath).readAsString();
    final token = _gateway.accessToken;
    final url =
        subtitle.url.startsWith('http')
            ? subtitle.url
            : '${_gateway.serverUrl}${subtitle.url}';
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        responseType: ResponseType.plain,
      ),
    );
    return response.data;
  }

  void dispose() => _dio.close();

  Future<String?> _resolveRedirect(
    String url,
    Map<String, String>? authHeaders,
  ) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          followRedirects: false,
          validateStatus:
              (status) => status != null && status >= 200 && status < 400,
          headers: {
            'User-Agent': DownloadService.aria2UserAgent,
            ...?authHeaders,
          },
        ),
      );

      final code = response.statusCode ?? 0;
      if (code >= 300 && code < 400) {
        final loc = response.headers.value('location');
        if (loc != null && loc.trim().isNotEmpty) {
          return Uri.parse(url).resolve(loc.trim()).toString();
        }
      }
    } catch (e) {
      LogService.instance.warn(
        'PlaybackSource',
        'Failed to resolve redirect: $e',
      );
    }
    return null;
  }

  Future<Map<String, String>?> _authHeadersFor(
    String playUrl,
    int? storageId,
  ) async {
    // WebDAV 存储：使用 BasicAuth
    if (storageId != null) {
      final storage = await _gateway.findStorage(storageId);
      if (storage != null && storage.type.toLowerCase() == 'webdav') {
        final settings = storage.settings;
        if (settings != null) {
          final webdavUrl = settings['url'];
          final username = settings['username'];
          final password = settings['password'];
          if (webdavUrl != null &&
              username != null &&
              password != null &&
              username.isNotEmpty) {
            final webdavUri = Uri.tryParse(webdavUrl);
            final playUri = Uri.tryParse(playUrl);
            if (HttpUtils.sameOrigin(webdavUri, playUri)) {
              return {
                'Authorization': HttpUtils.basicAuthHeader(username, password),
              };
            }
          }
        }
      }
    }

    // 非 WebDAV：如果 URL 与服务器同源，附带 Bearer Token
    final serverUrl = _gateway.serverUrl;
    final token = _gateway.accessToken;
    if (serverUrl != null && token != null) {
      final serverUri = Uri.tryParse(serverUrl);
      final playUri = Uri.tryParse(playUrl);
      if (HttpUtils.sameOrigin(serverUri, playUri)) {
        return {'Authorization': 'Bearer $token'};
      }
    }
    return null;
  }
}
