import '../models/models.dart';
import '../../core/constants/api_constants.dart';
import 'api_client.dart';

class AuthStatusResult {
  final bool setupRequired;
  AuthStatusResult({required this.setupRequired});
}

class AuthResult {
  final User user;
  final AuthTokens tokens;
  AuthResult({required this.user, required this.tokens});
}

class AuthService {
  final ApiClient _client;

  AuthService(this._client);

  Future<ApiResponse<AuthStatusResult>> getAuthStatus() async {
    return _client.get<AuthStatusResult>(
      ApiConstants.authStatus,
      fromJson: (json) {
        final data = json as Map<String, dynamic>;
        return AuthStatusResult(
          setupRequired: data['setup_required'] as bool? ?? false,
        );
      },
    );
  }

  Future<ApiResponse<AuthResult>> setup({
    required String username,
    required String password,
  }) async {
    return _client.post<AuthResult>(
      ApiConstants.authSetup,
      data: {'username': username, 'password': password},
      fromJson: (json) => _parseAuthResult(json as Map<String, dynamic>),
    );
  }

  Future<ApiResponse<AuthResult>> login({
    required String username,
    required String password,
  }) async {
    return _client.post<AuthResult>(
      ApiConstants.authLogin,
      data: {'username': username, 'password': password},
      fromJson: (json) => _parseAuthResult(json as Map<String, dynamic>),
    );
  }

  Future<ApiResponse<AuthTokens>> refresh({
    required String refreshToken,
  }) async {
    return _client.post<AuthTokens>(
      ApiConstants.authRefresh,
      data: {'refresh_token': refreshToken},
      fromJson: (json) {
        final data = json as Map<String, dynamic>;
        final tokens = data['tokens'] ?? data;
        return AuthTokens.fromJson(tokens as Map<String, dynamic>);
      },
    );
  }

  Future<ApiResponse<void>> logout({required String refreshToken}) async {
    return _client.post(
      ApiConstants.authLogout,
      data: {'refresh_token': refreshToken},
    );
  }

  Future<ApiResponse<User>> getMe() async {
    return _client.get<User>(
      ApiConstants.authMe,
      fromJson: (json) => User.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ApiResponse<void>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    return _client.put(
      ApiConstants.authPassword,
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
  }

  AuthResult _parseAuthResult(Map<String, dynamic> json) {
    return AuthResult(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
    );
  }
}
