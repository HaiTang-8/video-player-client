import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/services/aria2_service.dart';
import 'server_provider.dart';

@immutable
class Aria2Config {
  final bool enabled;
  final String rpcUrl;
  final String secret;

  const Aria2Config({
    this.enabled = false,
    this.rpcUrl = 'http://localhost:6800/jsonrpc',
    this.secret = '',
  });

  Aria2Config copyWith({bool? enabled, String? rpcUrl, String? secret}) {
    return Aria2Config(
      enabled: enabled ?? this.enabled,
      rpcUrl: rpcUrl ?? this.rpcUrl,
      secret: secret ?? this.secret,
    );
  }
}

final aria2ConfigProvider =
    StateNotifierProvider<Aria2ConfigNotifier, Aria2Config>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return Aria2ConfigNotifier(prefs);
});

class Aria2ConfigNotifier extends StateNotifier<Aria2Config> {
  final SharedPreferences _prefs;

  Aria2ConfigNotifier(this._prefs) : super(_loadConfig(_prefs));

  static Aria2Config _loadConfig(SharedPreferences prefs) {
    return Aria2Config(
      enabled: prefs.getBool(AppConstants.aria2EnabledKey) ?? false,
      rpcUrl: prefs.getString(AppConstants.aria2RpcUrlKey) ?? 'http://localhost:6800/jsonrpc',
      secret: prefs.getString(AppConstants.aria2RpcSecretKey) ?? '',
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.aria2EnabledKey, enabled);
    state = state.copyWith(enabled: enabled);
  }

  Future<void> setRpcUrl(String url) async {
    await _prefs.setString(AppConstants.aria2RpcUrlKey, url);
    state = state.copyWith(rpcUrl: url);
  }

  Future<void> setSecret(String secret) async {
    await _prefs.setString(AppConstants.aria2RpcSecretKey, secret);
    state = state.copyWith(secret: secret);
  }

  Future<void> updateConfig({bool? enabled, String? rpcUrl, String? secret}) async {
    if (enabled != null) await _prefs.setBool(AppConstants.aria2EnabledKey, enabled);
    if (rpcUrl != null) await _prefs.setString(AppConstants.aria2RpcUrlKey, rpcUrl);
    if (secret != null) await _prefs.setString(AppConstants.aria2RpcSecretKey, secret);
    state = state.copyWith(enabled: enabled, rpcUrl: rpcUrl, secret: secret);
  }
}

final aria2ServiceProvider = Provider<Aria2Service?>((ref) {
  final config = ref.watch(aria2ConfigProvider);
  if (!config.enabled || config.rpcUrl.isEmpty) return null;
  return Aria2Service(
    rpcUrl: config.rpcUrl,
    secret: config.secret.isNotEmpty ? config.secret : null,
  );
});
