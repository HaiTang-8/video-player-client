import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final aria2ConfigProvider = NotifierProvider<Aria2ConfigNotifier, Aria2Config>(Aria2ConfigNotifier.new);

class Aria2ConfigNotifier extends Notifier<Aria2Config> {
  @override
  Aria2Config build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return Aria2Config(
      enabled: prefs.getBool(AppConstants.aria2EnabledKey) ?? false,
      rpcUrl: prefs.getString(AppConstants.aria2RpcUrlKey) ?? 'http://localhost:6800/jsonrpc',
      secret: prefs.getString(AppConstants.aria2RpcSecretKey) ?? '',
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(AppConstants.aria2EnabledKey, enabled);
    state = state.copyWith(enabled: enabled);
  }

  Future<void> setRpcUrl(String url) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConstants.aria2RpcUrlKey, url);
    state = state.copyWith(rpcUrl: url);
  }

  Future<void> setSecret(String secret) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConstants.aria2RpcSecretKey, secret);
    state = state.copyWith(secret: secret);
  }

  Future<void> updateConfig({bool? enabled, String? rpcUrl, String? secret}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (enabled != null) await prefs.setBool(AppConstants.aria2EnabledKey, enabled);
    if (rpcUrl != null) await prefs.setString(AppConstants.aria2RpcUrlKey, rpcUrl);
    if (secret != null) await prefs.setString(AppConstants.aria2RpcSecretKey, secret);
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
