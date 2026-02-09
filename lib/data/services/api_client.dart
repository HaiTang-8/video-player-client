import 'package:dio/dio.dart';
import 'log_service.dart';

class AuthInterceptor extends Interceptor {
  String? Function() tokenGetter;
  Future<bool> Function()? onTokenExpired;

  bool _isRefreshing = false;
  final List<({RequestOptions options, ErrorInterceptorHandler handler})> _pendingRequests = [];

  AuthInterceptor({required this.tokenGetter, this.onTokenExpired});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokenGetter();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || onTokenExpired == null) {
      handler.next(err);
      return;
    }

    final path = err.requestOptions.path;
    if (path.contains('/auth/refresh') || path.contains('/auth/login')) {
      handler.next(err);
      return;
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
        final token = tokenGetter();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';
        final dio = Dio();
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (e) {
        handler.next(err);
      }

      final pending = List.of(_pendingRequests);
      _pendingRequests.clear();
      for (final req in pending) {
        final token = tokenGetter();
        req.options.headers['Authorization'] = 'Bearer $token';
        try {
          final dio = Dio();
          final response = await dio.fetch(req.options);
          req.handler.resolve(response);
        } catch (e) {
          req.handler.next(DioException(requestOptions: req.options, error: e));
        }
      }
    } else {
      final pending = List.of(_pendingRequests);
      _pendingRequests.clear();
      handler.next(err);
      for (final req in pending) {
        req.handler.next(DioException(requestOptions: req.options, error: 'Token refresh failed'));
      }
    }
  }
}

/// API 客户端封装
class ApiClient {
  final Dio _dio;
  final void Function(String)? onError;

  ApiClient({required String baseUrl, this.onError})
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
      );

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

    // Avoid pretty/ANSI console output. Keep messages single-line & stable.
    LogService.instance.error('ApiClient', 'API Error: $errorMessage (${e.type}) [${e.requestOptions.method} ${e.requestOptions.path}]');

    onError?.call(errorMessage);

    return ApiResponse<T>(success: false, error: errorMessage);
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
