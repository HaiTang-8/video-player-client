import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/models/models.dart';
import '../data/services/api_client.dart';
import '../data/services/auth_service.dart';
import 'download_provider.dart';
import 'server_provider.dart';
import 'watch_history_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, setupRequired }

class AuthState {
  final AuthStatus status;
  final User? user;
  final AuthTokens? tokens;
  final bool authEnabled;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.tokens,
    this.authEnabled = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    AuthTokens? tokens,
    bool? authEnabled,
    bool clearUser = false,
    bool clearTokens = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      tokens: clearTokens ? null : (tokens ?? this.tokens),
      authEnabled: authEnabled ?? this.authEnabled,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  AuthInterceptor? _interceptor;

  @override
  AuthState build() {
    ref.listen(apiClientProvider, (prev, next) {
      _setupInterceptor(next);
    });
    return const AuthState();
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String? get _serverId => ref.read(serverListProvider).currentServerId;

  ApiClient? get _apiClient => ref.read(apiClientProvider);

  void _setupInterceptor(ApiClient? client) {
    if (client == null) return;
    _interceptor?.let(client.removeInterceptor);
    _interceptor = AuthInterceptor(
      tokenGetter: () => state.tokens?.accessToken,
      onTokenExpired: () => refreshToken(),
    );
    client.addInterceptor(_interceptor!);
  }

  Future<void> checkAuthStatus() async {
    final client = _apiClient;
    if (client == null) return;

    _setupInterceptor(client);
    final authService = AuthService(client);

    final statusResp = await authService.getAuthStatus();
    if (!statusResp.isSuccess || statusResp.data == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated, authEnabled: false);
      return;
    }

    final setupRequired = statusResp.data!.setupRequired;
    if (setupRequired) {
      state = state.copyWith(status: AuthStatus.setupRequired, authEnabled: true);
      return;
    }

    state = state.copyWith(authEnabled: true);

    final savedTokens = _loadTokens();
    if (savedTokens == null) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        clearTokens: true,
      );
      return;
    }

    state = state.copyWith(tokens: savedTokens);

    final meResp = await authService.getMe();
    if (meResp.isSuccess && meResp.data != null) {
      state = state.copyWith(status: AuthStatus.authenticated, user: meResp.data);
      _saveUser(meResp.data!);
    } else {
      final refreshed = await refreshToken();
      if (refreshed) {
        final retryMe = await authService.getMe();
        if (retryMe.isSuccess && retryMe.data != null) {
          state = state.copyWith(status: AuthStatus.authenticated, user: retryMe.data);
          _saveUser(retryMe.data!);
          return;
        }
      }
      _clearStorage();
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        clearTokens: true,
      );
    }
  }

  Future<void> login(String username, String password) async {
    final client = _apiClient;
    if (client == null) throw Exception('未连接到服务器');

    final authService = AuthService(client);
    final resp = await authService.login(username: username, password: password);

    if (!resp.isSuccess || resp.data == null) {
      throw Exception(resp.error ?? '登录失败');
    }

    final result = resp.data!;
    _saveTokens(result.tokens);
    _saveUser(result.user);
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: result.user,
      tokens: result.tokens,
    );
  }

  Future<void> setup(String username, String password) async {
    final client = _apiClient;
    if (client == null) throw Exception('未连接到服务器');

    final authService = AuthService(client);
    final resp = await authService.setup(username: username, password: password);

    if (!resp.isSuccess || resp.data == null) {
      throw Exception(resp.error ?? '初始设置失败');
    }

    final result = resp.data!;
    _saveTokens(result.tokens);
    _saveUser(result.user);
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: result.user,
      tokens: result.tokens,
    );
  }

  Future<void> logout() async {
    try {
      await ref.read(downloadManagerProvider.notifier).pauseAllDownloads();
    } catch (_) {}

    final client = _apiClient;
    final tokens = state.tokens;
    if (client != null && tokens != null) {
      final authService = AuthService(client);
      await authService.logout(refreshToken: tokens.refreshToken);
    }
    ref.invalidate(watchHistoryProvider);
    _clearStorage();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearTokens: true,
    );
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final client = _apiClient;
    if (client == null) throw Exception('未连接到服务器');

    final authService = AuthService(client);
    final resp = await authService.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    if (!resp.isSuccess) {
      throw Exception(resp.error ?? '修改密码失败');
    }

    _clearStorage();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearTokens: true,
    );
  }

  Future<bool> refreshToken() async {
    final client = _apiClient;
    final tokens = state.tokens;
    if (client == null || tokens == null) return false;

    final authService = AuthService(client);
    final resp = await authService.refresh(refreshToken: tokens.refreshToken);

    if (resp.isSuccess && resp.data != null) {
      final newTokens = resp.data!;
      _saveTokens(newTokens);
      state = state.copyWith(tokens: newTokens);
      return true;
    }
    _clearStorage();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearTokens: true,
    );
    return false;
  }

  void reset() {
    state = const AuthState();
  }

  AuthTokens? _loadTokens() {
    final sid = _serverId;
    if (sid == null) return null;
    final json = _prefs.getString(AppConstants.authTokensKey(sid));
    if (json == null) return null;
    try {
      return AuthTokens.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _saveTokens(AuthTokens tokens) {
    final sid = _serverId;
    if (sid == null) return;
    _prefs.setString(AppConstants.authTokensKey(sid), jsonEncode(tokens.toJson()));
  }

  void _saveUser(User user) {
    final sid = _serverId;
    if (sid == null) return;
    _prefs.setString(AppConstants.authUserKey(sid), jsonEncode(user.toJson()));
  }

  void _clearStorage() {
    final sid = _serverId;
    if (sid == null) return;
    _prefs.remove(AppConstants.authTokensKey(sid));
    _prefs.remove(AppConstants.authUserKey(sid));
  }
}

extension _NullableExtension<T> on T? {
  void let(void Function(T) action) {
    if (this != null) action(this as T);
  }
}
