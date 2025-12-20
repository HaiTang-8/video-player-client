import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// API 客户端封装
class ApiClient {
  final Dio _dio;
  final Logger _logger = Logger();

  ApiClient({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => _logger.d(obj),
    ));
  }

  /// 更新 baseUrl
  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }

  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? fromJson,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
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
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
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
  }) async {
    try {
      final response =
          await _dio.delete(path, queryParameters: queryParameters);
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    }
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
      final success = data['success'] as bool? ??
          (data['status'] == 'ok') ||
          (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300);
      final message = data['message'] as String?;
      final error = data['error'] as String?;

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

    return ApiResponse<T>(
      success: false,
      error: '响应格式错误',
    );
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

    _logger.e('API Error: $errorMessage', error: e);

    return ApiResponse<T>(
      success: false,
      error: errorMessage,
    );
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
