import 'dart:convert';

import 'package:dio/dio.dart';
import 'log_service.dart';
import 'proxy_http_client_adapter.dart';

const _retryDioExtraKey = 'retry_dio';

void configureDioAuthRetry(Dio dio) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra[_retryDioExtraKey] = dio;
        handler.next(options);
      },
    ),
  );
}

class AuthInterceptor extends Interceptor {
  final String? Function() tokenGetter;
  final Future<bool> Function()? onTokenExpired;
  final bool Function(RequestOptions options)? shouldAttachToken;
  final bool Function(RequestOptions options)? shouldRefreshOn401;

  bool _isRefreshing = false;
  final List<({RequestOptions options, ErrorInterceptorHandler handler})>
  _pendingRequests = [];

  AuthInterceptor({
    required this.tokenGetter,
    this.onTokenExpired,
    this.shouldAttachToken,
    this.shouldRefreshOn401,
  });

  dynamic _getHeaderValue(Map<String, dynamic> headers, String headerName) {
    final name = headerName.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  bool _shouldAttach(RequestOptions options) {
    final fn = shouldAttachToken;
    if (fn == null) return true;
    try {
      return fn(options);
    } catch (_) {
      return false;
    }
  }

  bool _shouldRefresh(RequestOptions options) {
    final fn = shouldRefreshOn401 ?? shouldAttachToken;
    if (fn == null) return true;
    try {
      return fn(options);
    } catch (_) {
      return false;
    }
  }

  void _setBearerHeaderIfNeeded(RequestOptions options) {
    if (!_shouldAttach(options)) return;
    final token = tokenGetter();
    if (token == null || token.isEmpty) return;

    final existing = _getHeaderValue(options.headers, 'Authorization');
    if (existing != null) {
      final v = existing.toString().trimLeft();
      if (!v.toLowerCase().startsWith('bearer ')) {
        // Keep caller-provided auth (e.g. Basic) untouched.
        return;
      }
    }
    options.headers['Authorization'] = 'Bearer $token';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _setBearerHeaderIfNeeded(options);
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || onTokenExpired == null) {
      handler.next(err);
      return;
    }

    final path = err.requestOptions.path;
    if (path.contains('/auth/refresh') ||
        path.contains('/auth/login') ||
        path.contains('/auth/setup')) {
      handler.next(err);
      return;
    }

    if (!_shouldRefresh(err.requestOptions)) {
      handler.next(err);
      return;
    }

    final existingAuth = _getHeaderValue(
      err.requestOptions.headers,
      'Authorization',
    );
    if (existingAuth != null) {
      final v = existingAuth.toString().trimLeft().toLowerCase();
      if (!v.startsWith('bearer ')) {
        handler.next(err);
        return;
      }
    }

    if (_isRefreshing) {
      _pendingRequests.add((options: err.requestOptions, handler: handler));
      return;
    }

    _isRefreshing = true;
    final success = await onTokenExpired!();
    _isRefreshing = false;

    if (success) {
      try {
        _setBearerHeaderIfNeeded(err.requestOptions);
        final dio =
            err.requestOptions.extra[_retryDioExtraKey] as Dio? ?? Dio();
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (e) {
        handler.next(err);
      }

      final pending = List.of(_pendingRequests);
      _pendingRequests.clear();
      for (final req in pending) {
        _setBearerHeaderIfNeeded(req.options);
        try {
          final dio = req.options.extra[_retryDioExtraKey] as Dio? ?? Dio();
          final response = await dio.fetch(req.options);
          req.handler.resolve(response);
        } catch (e) {
          req.handler.next(
            DioException(
              requestOptions: req.options,
              error: e,
              message: 'Retry after token refresh failed: $e',
            ),
          );
        }
      }
    } else {
      final pending = List.of(_pendingRequests);
      _pendingRequests.clear();
      handler.next(err);
      for (final req in pending) {
        req.handler.next(
          DioException(
            requestOptions: req.options,
            error: 'Token refresh failed',
            message: 'Token refresh failed',
          ),
        );
      }
    }
  }
}

/// API 客户端封装
class ApiClient {
  final Dio _dio;
  final void Function(String)? onError;

  ApiClient({required String baseUrl, String? proxyUrl, this.onError})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    configureDioProxy(_dio, proxyUrl);
    configureDioAuthRetry(_dio);
  }

  /// 添加拦截器
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 移除拦截器
  void removeInterceptor(Interceptor interceptor) {
    _dio.interceptors.remove(interceptor);
  }

  /// 更新 baseUrl
  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }

  /// 关闭 Dio 客户端，释放资源
  void close() {
    _dio.close();
  }

  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? fromJson,
    // 可选：针对“AI 整理/长任务”单独放宽超时，避免 Dio 默认 30s 触发“接收超时”
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: _buildOptions(receiveTimeout: receiveTimeout),
      );
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// 打开服务端事件流
  Stream<String> openEventStream(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.get<ResponseBody>(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: receiveTimeout,
        headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
      ),
    );

    final body = response.data;
    if (body == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: '响应流为空',
      );
    }

    yield* body.stream
        .map<List<int>>((chunk) => chunk)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
  }

  /// POST 请求
  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? fromJson,
    // 可选：针对“AI 整理/长任务”单独放宽超时，避免 Dio 默认 30s 触发“接收超时”
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _buildOptions(receiveTimeout: receiveTimeout),
      );
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? fromJson,
    // 可选：针对"AI 整理/长任务"单独放宽超时，避免 Dio 默认 30s 触发"接收超时"
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        queryParameters: queryParameters,
        options: _buildOptions(receiveTimeout: receiveTimeout),
      );
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// PUT 请求
  Future<ApiResponse<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// 构建 Dio Options（按需覆盖默认超时）
  ///
  /// 说明：
  /// - BaseOptions 里设置的是全局默认超时（更偏“常规接口”）
  /// - AI 整理属于“长任务”，这里允许为单个请求单独放宽 receiveTimeout
  Options? _buildOptions({Duration? receiveTimeout}) {
    if (receiveTimeout == null) return null;
    return Options(receiveTimeout: receiveTimeout);
  }

  /// 处理响应
  ApiResponse<T> _handleResponse<T>(
    Response response,
    T Function(dynamic json)? fromJson,
  ) {
    final data = response.data;

    if (data is Map<String, dynamic>) {
      // 兼容两种响应格式：
      // 1. 标准格式: {"success": true, "data": ...}
      // 2. 健康检查格式: {"status": "ok", "message": ...}
      final success =
          data['success'] == true ||
          data['status'] == 'ok' ||
          (response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300 &&
              data['success'] != false);
      final message = data['message']?.toString();
      final error = data['error']?.toString();

      if (success) {
        final responseData = data['data'];
        final total = data['total'] as int?;
        final page = data['page'] as int?;
        final pageSize = data['page_size'] as int?;

        T? parsedData;
        if (fromJson != null && responseData != null) {
          parsedData = fromJson(responseData);
        }

        return ApiResponse<T>(
          success: true,
          data: parsedData,
          message: message,
          total: total,
          page: page,
          pageSize: pageSize,
        );
      } else {
        return ApiResponse<T>(
          success: false,
          error: error ?? message ?? '请求失败',
        );
      }
    }

    return ApiResponse<T>(success: false, error: '响应格式错误');
  }

  /// 处理错误
  ApiResponse<T> _handleError<T>(DioException e) {
    String errorMessage;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        errorMessage = '连接超时';
        break;
      case DioExceptionType.sendTimeout:
        errorMessage = '发送超时';
        break;
      case DioExceptionType.receiveTimeout:
        errorMessage = '接收超时';
        break;
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          errorMessage = data['error'] ?? '服务器错误 ($statusCode)';
        } else {
          errorMessage = '服务器错误 ($statusCode)';
        }
        // 404 是正常业务场景（如首次播放无观看记录），不触发全局错误提示
        if (statusCode == 404) {
          return ApiResponse<T>(success: false, error: errorMessage);
        }
        // auth 相关错误由调用方局部处理，不触发全局错误提示
        if (e.requestOptions.path.contains('/auth/')) {
          return ApiResponse<T>(success: false, error: errorMessage);
        }
        break;
      case DioExceptionType.cancel:
        errorMessage = '请求已取消';
        break;
      case DioExceptionType.connectionError:
        errorMessage = '无法连接到服务器';
        break;
      default:
        errorMessage = e.message ?? '网络错误';
    }

    final details = _formatDioErrorDetails(e);

    // Avoid pretty/ANSI console output. Keep messages single-line & stable.
    LogService.instance.error(
      'ApiClient',
      'API Error: $errorMessage (${e.type}) [${e.requestOptions.method} ${e.requestOptions.path}]$details',
    );

    onError?.call(errorMessage);

    return ApiResponse<T>(success: false, error: errorMessage);
  }

  String _formatDioErrorDetails(DioException e) {
    final parts = <String>[];
    final statusCode = e.response?.statusCode;
    if (statusCode != null) {
      parts.add('status=$statusCode');
    }

    final uri = e.requestOptions.uri.toString();
    if (uri.isNotEmpty) {
      parts.add('url=${_compactLogValue(uri)}');
    }

    final message = e.message;
    if (message != null && message.isNotEmpty) {
      parts.add('message=${_compactLogValue(message)}');
    }

    final rawError = e.error;
    if (rawError != null) {
      parts.add('error=${_compactLogValue(rawError.toString())}');
    }

    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      final responseError = responseData['error'] ?? responseData['message'];
      if (responseError != null) {
        parts.add('response=${_compactLogValue(responseError.toString())}');
      }
    } else if (responseData is String && responseData.isNotEmpty) {
      parts.add('response=${_compactLogValue(responseData)}');
    }

    if (parts.isEmpty) return '';
    return ' {${parts.join(', ')}}';
  }

  String _compactLogValue(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 240) return compact;
    return '${compact.substring(0, 240)}...';
  }
}

/// API 响应封装
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final String? error;
  final int? total;
  final int? page;
  final int? pageSize;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
    this.total,
    this.page,
    this.pageSize,
  });

  bool get isSuccess => success && error == null;
  bool get hasData => data != null;
  bool get hasPagination => total != null && page != null && pageSize != null;
}
