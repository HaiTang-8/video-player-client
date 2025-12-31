import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/models/server_config.dart';
import '../data/services/api_client.dart';
import '../data/services/storage_service.dart';
import 'error_notification_provider.dart';

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖此 Provider');
});

/// 服务器列表状态
class ServerListState {
  final List<ServerConfig> servers;
  final String? currentServerId;

  ServerListState({required this.servers, this.currentServerId});

  ServerConfig? get currentServer {
    if (currentServerId == null) return null;
    try {
      return servers.firstWhere((s) => s.id == currentServerId);
    } catch (_) {
      return servers.isNotEmpty ? servers.first : null;
    }
  }

  ServerListState copyWith({List<ServerConfig>? servers, String? currentServerId}) {
    return ServerListState(
      servers: servers ?? this.servers,
      currentServerId: currentServerId ?? this.currentServerId,
    );
  }
}

/// 服务器列表 Provider
final serverListProvider =
    StateNotifierProvider<ServerListNotifier, ServerListState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ServerListNotifier(prefs);
});

class ServerListNotifier extends StateNotifier<ServerListState> {
  final SharedPreferences _prefs;

  ServerListNotifier(this._prefs) : super(ServerListState(servers: [])) {
    _loadServers();
  }

  void _loadServers() {
    final listJson = _prefs.getString(AppConstants.serverListKey);
    final currentId = _prefs.getString(AppConstants.currentServerIdKey);

    List<ServerConfig> servers = [];
    if (listJson != null) {
      final List<dynamic> list = jsonDecode(listJson);
      servers = list.map((e) => ServerConfig.fromJson(e)).toList();
    }

    // 迁移旧版单服务器数据
    if (servers.isEmpty) {
      final oldUrl = _prefs.getString(AppConstants.serverUrlKey);
      if (oldUrl != null && oldUrl.isNotEmpty) {
        final migrated = ServerConfig.create(name: '默认服务器', url: oldUrl);
        servers = [migrated];
        _saveServers(servers);
        _prefs.setString(AppConstants.currentServerIdKey, migrated.id);
        state = ServerListState(servers: servers, currentServerId: migrated.id);
        return;
      }
    }

    state = ServerListState(servers: servers, currentServerId: currentId);
  }

  Future<void> _saveServers(List<ServerConfig> servers) async {
    final json = jsonEncode(servers.map((e) => e.toJson()).toList());
    await _prefs.setString(AppConstants.serverListKey, json);
  }

  Future<void> addServer(String name, String url) async {
    final server = ServerConfig.create(name: name, url: url);
    final newServers = [...state.servers, server];
    await _saveServers(newServers);

    // 如果是第一个服务器，自动设为当前
    String? newCurrentId = state.currentServerId;
    if (newCurrentId == null) {
      newCurrentId = server.id;
      await _prefs.setString(AppConstants.currentServerIdKey, newCurrentId);
    }

    state = state.copyWith(servers: newServers, currentServerId: newCurrentId);
  }

  Future<void> removeServer(String id) async {
    final newServers = state.servers.where((s) => s.id != id).toList();
    await _saveServers(newServers);

    String? newCurrentId = state.currentServerId;
    if (newCurrentId == id) {
      newCurrentId = newServers.isNotEmpty ? newServers.first.id : null;
      if (newCurrentId != null) {
        await _prefs.setString(AppConstants.currentServerIdKey, newCurrentId);
      } else {
        await _prefs.remove(AppConstants.currentServerIdKey);
      }
    }

    state = state.copyWith(servers: newServers, currentServerId: newCurrentId);
  }

  Future<void> updateServer(String id, {String? name, String? url}) async {
    final newServers = state.servers.map((s) {
      if (s.id == id) {
        return s.copyWith(name: name, url: url);
      }
      return s;
    }).toList();
    await _saveServers(newServers);
    state = state.copyWith(servers: newServers);
  }

  Future<void> setCurrentServer(String id) async {
    await _prefs.setString(AppConstants.currentServerIdKey, id);
    state = state.copyWith(currentServerId: id);
  }
}

/// 当前服务器 URL Provider（兼容旧接口）
final serverUrlProvider = Provider<String?>((ref) {
  final serverState = ref.watch(serverListProvider);
  return serverState.currentServer?.url;
});

/// API Client Provider
final apiClientProvider = Provider<ApiClient?>((ref) {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null || serverUrl.isEmpty) {
    return null;
  }
  return ApiClient(
    baseUrl: serverUrl,
    onError: (msg) => ref.read(errorNotificationProvider.notifier).notify(msg),
  );
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
