import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/models/server_config.dart';
import '../data/services/api_client.dart';
import '../data/services/storage_service.dart';
import 'auth_provider.dart';
import 'error_notification_provider.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖此 Provider');
});

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

final serverListProvider = NotifierProvider<ServerListNotifier, ServerListState>(ServerListNotifier.new);

class ServerListNotifier extends Notifier<ServerListState> {
  @override
  ServerListState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _loadServers(prefs);
  }

  ServerListState _loadServers(SharedPreferences prefs) {
    final listJson = prefs.getString(AppConstants.serverListKey);
    final currentId = prefs.getString(AppConstants.currentServerIdKey);

    List<ServerConfig> servers = [];
    if (listJson != null) {
      final List<dynamic> list = jsonDecode(listJson);
      servers = list.map((e) => ServerConfig.fromJson(e)).toList();
    }

    if (servers.isEmpty) {
      final oldUrl = prefs.getString(AppConstants.serverUrlKey);
      if (oldUrl != null && oldUrl.isNotEmpty) {
        final migrated = ServerConfig.create(name: '默认服务器', url: oldUrl);
        servers = [migrated];
        _saveServers(servers);
        prefs.setString(AppConstants.currentServerIdKey, migrated.id);
        return ServerListState(servers: servers, currentServerId: migrated.id);
      }
    }

    return ServerListState(servers: servers, currentServerId: currentId);
  }

  Future<void> _saveServers(List<ServerConfig> servers) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final json = jsonEncode(servers.map((e) => e.toJson()).toList());
    await prefs.setString(AppConstants.serverListKey, json);
  }

  Future<void> addServer(String name, String url) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final server = ServerConfig.create(name: name, url: url);
    final newServers = [...state.servers, server];
    await _saveServers(newServers);

    String? newCurrentId = state.currentServerId;
    if (newCurrentId == null) {
      newCurrentId = server.id;
      await prefs.setString(AppConstants.currentServerIdKey, newCurrentId);
    }

    state = state.copyWith(servers: newServers, currentServerId: newCurrentId);
  }

  Future<void> removeServer(String id) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final newServers = state.servers.where((s) => s.id != id).toList();
    await _saveServers(newServers);

    String? newCurrentId = state.currentServerId;
    if (newCurrentId == id) {
      newCurrentId = newServers.isNotEmpty ? newServers.first.id : null;
      if (newCurrentId != null) {
        await prefs.setString(AppConstants.currentServerIdKey, newCurrentId);
      } else {
        await prefs.remove(AppConstants.currentServerIdKey);
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
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConstants.currentServerIdKey, id);
    state = state.copyWith(currentServerId: id);
  }
}

final serverUrlProvider = Provider<String?>((ref) {
  final serverState = ref.watch(serverListProvider);
  return serverState.currentServer?.url;
});

final apiClientProvider = Provider<ApiClient?>((ref) {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null || serverUrl.isEmpty) {
    return null;
  }
  final client = ApiClient(
    baseUrl: serverUrl,
    onError: (msg) => ref.read(errorNotificationProvider.notifier).notify(msg),
  );
  // 当 Provider 被销毁时关闭 Dio 客户端
  ref.onDispose(() {
    client.close();
  });
  return client;
});

enum ServerConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

final serverConnectionProvider = NotifierProvider<ServerConnectionNotifier, ServerConnectionState>(ServerConnectionNotifier.new);

class ServerConnectionNotifier extends Notifier<ServerConnectionState> {
  @override
  ServerConnectionState build() => ServerConnectionState.disconnected;

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
    final serverUrl = ref.read(serverUrlProvider);
    if (serverUrl != null && serverUrl.isNotEmpty) {
      final success = await testConnection(serverUrl);
      if (success) {
        ref.read(authProvider.notifier).checkAuthStatus();
      }
    }
  }

  void setDisconnected() {
    state = ServerConnectionState.disconnected;
  }
}
