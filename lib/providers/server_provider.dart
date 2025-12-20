import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/services/api_client.dart';
import '../data/services/storage_service.dart';

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖此 Provider');
});

/// 服务器 URL Provider
final serverUrlProvider = StateNotifierProvider<ServerUrlNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ServerUrlNotifier(prefs);
});

class ServerUrlNotifier extends StateNotifier<String?> {
  final SharedPreferences _prefs;

  ServerUrlNotifier(this._prefs) : super(_prefs.getString(AppConstants.serverUrlKey));

  Future<void> setServerUrl(String url) async {
    await _prefs.setString(AppConstants.serverUrlKey, url);
    state = url;
  }

  Future<void> clearServerUrl() async {
    await _prefs.remove(AppConstants.serverUrlKey);
    state = null;
  }
}

/// API Client Provider
final apiClientProvider = Provider<ApiClient?>((ref) {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null || serverUrl.isEmpty) {
    return null;
  }
  return ApiClient(baseUrl: serverUrl);
});

/// 服务器连接状态
enum ServerConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// 服务器连接状态 Provider
final serverConnectionProvider =
    StateNotifierProvider<ServerConnectionNotifier, ServerConnectionState>((ref) {
  return ServerConnectionNotifier(ref);
});

class ServerConnectionNotifier extends StateNotifier<ServerConnectionState> {
  final Ref _ref;

  ServerConnectionNotifier(this._ref) : super(ServerConnectionState.disconnected);

  /// 测试服务器连接
  Future<bool> testConnection(String url) async {
    state = ServerConnectionState.connecting;
    try {
      final client = ApiClient(baseUrl: url);
      final storageService = StorageService(client);
      final response = await storageService.healthCheck();

      if (response.isSuccess) {
        state = ServerConnectionState.connected;
        return true;
      } else {
        state = ServerConnectionState.error;
        return false;
      }
    } catch (e) {
      state = ServerConnectionState.error;
      return false;
    }
  }

  /// 连接到已保存的服务器
  Future<void> connectToSavedServer() async {
    final serverUrl = _ref.read(serverUrlProvider);
    if (serverUrl != null && serverUrl.isNotEmpty) {
      await testConnection(serverUrl);
    }
  }

  void setDisconnected() {
    state = ServerConnectionState.disconnected;
  }
}
