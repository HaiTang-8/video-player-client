import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/constants/api_constants.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/server_config.dart';
import '../../data/services/proxy_http_client_adapter.dart';
import '../../providers/providers.dart';

enum _ProxyType {
  none('', '不使用代理', 0),
  http('http', 'HTTP', 7890),
  https('https', 'HTTPS', 7890),
  socks5('socks5', 'SOCKS5', 1080);

  const _ProxyType(this.scheme, this.label, this.defaultPort);

  final String scheme;
  final String label;
  final int defaultPort;
}

class _ProxyFormData {
  final _ProxyType type;
  final String host;
  final String port;
  final String username;
  final String password;

  const _ProxyFormData({
    required this.type,
    this.host = '',
    this.port = '',
    this.username = '',
    this.password = '',
  });
}

class _ProxyTestResult {
  final bool success;
  final String message;

  const _ProxyTestResult({required this.success, required this.message});
}

class _ProxyIpInfo {
  final String ip;
  final String country;
  final String region;
  final String city;

  const _ProxyIpInfo({
    required this.ip,
    this.country = '',
    this.region = '',
    this.city = '',
  });

  bool get hasLocation =>
      country.trim().isNotEmpty ||
      region.trim().isNotEmpty ||
      city.trim().isNotEmpty;

  String get displayText {
    final location = [
      country,
      region,
      city,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    return hasLocation ? '$ip $location' : '$ip（地理位置查询失败）';
  }
}

class ServerConfigScreen extends ConsumerStatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  ConsumerState<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends ConsumerState<ServerConfigScreen> {
  bool _isConnecting = false;
  String? _connectingServerId;

  Future<void> _connectToServer(ServerConfig server) async {
    setState(() {
      _isConnecting = true;
      _connectingServerId = server.id;
    });

    final connectionNotifier = ref.read(serverConnectionProvider.notifier);
    final success = await connectionNotifier.testConnection(
      server.url,
      proxyUrl: server.proxyUrl,
    );

    if (!mounted) return;

    if (success) {
      await ref.read(serverListProvider.notifier).setCurrentServer(server.id);
      ref.read(authProvider.notifier).checkAuthStatus();
    } else {
      DialogUtils.showToast(
        context: context,
        message: '无法连接到服务器',
        isError: true,
      );
    }

    setState(() {
      _isConnecting = false;
      _connectingServerId = null;
    });
  }

  _ProxyType _proxyTypeFromScheme(String scheme) {
    return _ProxyType.values.firstWhere(
      (type) => type.scheme == scheme,
      orElse: () => _ProxyType.none,
    );
  }

  _ProxyFormData _parseProxyFormData(String proxyUrl) {
    final value = proxyUrl.trim();
    if (value.isEmpty) return const _ProxyFormData(type: _ProxyType.none);

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) {
      return const _ProxyFormData(type: _ProxyType.none);
    }

    final type = _proxyTypeFromScheme(uri.scheme);
    if (type == _ProxyType.none) {
      return const _ProxyFormData(type: _ProxyType.none);
    }

    var username = '';
    var password = '';
    if (uri.userInfo.isNotEmpty) {
      final separator = uri.userInfo.indexOf(':');
      if (separator >= 0) {
        username = Uri.decodeComponent(uri.userInfo.substring(0, separator));
        password = Uri.decodeComponent(uri.userInfo.substring(separator + 1));
      } else {
        username = Uri.decodeComponent(uri.userInfo);
      }
    }

    return _ProxyFormData(
      type: type,
      host: uri.host,
      port: (uri.hasPort ? uri.port : type.defaultPort).toString(),
      username: username,
      password: password,
    );
  }

  String? _buildProxyUrl({
    required _ProxyType type,
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
  }) {
    if (type == _ProxyType.none) return '';

    final host = hostController.text.trim();
    if (host.isEmpty) return null;

    final portText = portController.text.trim();
    final port = portText.isEmpty ? type.defaultPort : int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) return null;

    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty && password.isNotEmpty) return null;

    return Uri(
      scheme: type.scheme,
      userInfo: username.isEmpty ? null : '$username:$password',
      host: host,
      port: port,
    ).toString();
  }

  Future<_ProxyTestResult> _testProxyConnection({
    required String baseUrl,
    required String proxyUrl,
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    configureDioProxy(dio, proxyUrl);

    try {
      final ipInfo = await _fetchProxyIpInfo(dio);
      final backendOk = await _checkBackendHealth(dio);
      if (backendOk) {
        final ipMessage =
            ipInfo == null ? '出口 IP：查询失败' : '出口 IP：${ipInfo.displayText}';
        return _ProxyTestResult(success: true, message: '$ipMessage\n后端连接：正常');
      }
      final ipMessage =
          ipInfo == null ? '出口 IP：查询失败' : '出口 IP：${ipInfo.displayText}';
      return _ProxyTestResult(success: false, message: '$ipMessage\n后端连接：失败');
    } on DioException catch (e) {
      final message = _proxyDioErrorMessage(e);
      return _ProxyTestResult(success: false, message: message);
    } catch (e) {
      return _ProxyTestResult(
        success: false,
        message: '代理检测失败：${_errorDetail(e)}',
      );
    } finally {
      dio.close();
    }
  }

  Future<_ProxyIpInfo?> _fetchProxyIpInfo(Dio dio) async {
    for (final endpoint in const [
      'https://ipwho.is/?lang=zh-CN',
      'http://ip-api.com/json?lang=zh-CN',
      'https://api.ipify.org?format=json',
    ]) {
      try {
        final response = await dio.get(endpoint);
        final info = _parseProxyIpInfo(response.data);
        if (info != null) return info;
      } catch (_) {}
    }
    return null;
  }

  _ProxyIpInfo? _parseProxyIpInfo(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final ip = (data['ip'] ?? data['query'])?.toString().trim() ?? '';
    if (ip.isEmpty) return null;

    final success = data['success'];
    if (success is bool && !success) return null;
    final status = data['status']?.toString().trim().toLowerCase();
    if (status != null && status.isNotEmpty && status != 'success') {
      return null;
    }

    return _ProxyIpInfo(
      ip: ip,
      country:
          (data['country'] ??
                  data['country_name'] ??
                  data['countryCode'] ??
                  data['country_code'])
              ?.toString()
              .trim() ??
          '',
      region:
          (data['regionName'] ?? data['region'] ?? data['region_name'])
              ?.toString()
              .trim() ??
          '',
      city: data['city']?.toString().trim() ?? '',
    );
  }

  Future<bool> _checkBackendHealth(Dio dio) async {
    final response = await dio.get(ApiConstants.health);
    final data = response.data;
    if (data is! Map<String, dynamic>) return false;
    return data['status'] == 'ok' || data['success'] == true;
  }

  String _proxyDioErrorMessage(DioException e) {
    final detail = _dioErrorDetail(e);
    final suffix = detail == null ? '' : '：$detail';
    return switch (e.type) {
      DioExceptionType.connectionTimeout => '代理连接超时$suffix',
      DioExceptionType.receiveTimeout => '后端响应超时$suffix',
      DioExceptionType.sendTimeout => '请求发送超时$suffix',
      DioExceptionType.badResponse =>
        '后端返回错误 (${e.response?.statusCode ?? '-'})$suffix',
      DioExceptionType.connectionError => '无法通过代理连接后端$suffix',
      _ => '代理检测失败$suffix',
    };
  }

  String? _dioErrorDetail(DioException e) {
    final error = e.error;
    if (error != null) return _errorDetail(error);
    final message = e.message?.trim();
    return message == null || message.isEmpty ? null : message;
  }

  String _errorDetail(Object error) {
    var text = error.toString().trim();
    if (text.startsWith('SocketException: ')) {
      text = text.substring('SocketException: '.length);
    }
    return text.isEmpty ? '未知错误' : text;
  }

  Widget _buildProxyForm({
    required _ProxyType proxyType,
    required ValueChanged<_ProxyType> onProxyTypeChanged,
    required VoidCallback onProxyFieldsChanged,
    required VoidCallback onTestProxy,
    required bool isTestingProxy,
    required _ProxyTestResult? proxyTestResult,
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
    required FocusNode hostFocusNode,
    required FocusNode portFocusNode,
    required FocusNode usernameFocusNode,
    required FocusNode passwordFocusNode,
  }) {
    final enabled = proxyType != _ProxyType.none;
    final theme = Theme.of(context);
    final proxyHost = hostController.text.trim();
    final proxyPort = portController.text.trim();
    final proxySummary =
        enabled && proxyHost.isNotEmpty
            ? '${proxyType.label} $proxyHost:${proxyPort.isEmpty ? proxyType.defaultPort : proxyPort}'
            : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: shadcn.Select<_ProxyType>(
            value: proxyType,
            itemBuilder: (context, item) => Text(item.label),
            onChanged: (value) {
              if (value == null) return;
              onProxyTypeChanged(value);
            },
            popup:
                shadcn.SelectPopup(
                  items: shadcn.SelectItemList(
                    children:
                        _ProxyType.values
                            .map(
                              (type) => shadcn.SelectItemButton(
                                value: type,
                                child: Text(type.label),
                              ),
                            )
                            .toList(),
                  ),
                ).call,
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: shadcn.TextField(
                  controller: hostController,
                  focusNode: hostFocusNode,
                  placeholder: const Text('代理地址'),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onProxyFieldsChanged(),
                  onSubmitted: (_) => portFocusNode.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: shadcn.TextField(
                  controller: portController,
                  focusNode: portFocusNode,
                  placeholder: Text('${proxyType.defaultPort}'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onProxyFieldsChanged(),
                  onSubmitted: (_) => usernameFocusNode.requestFocus(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          shadcn.TextField(
            controller: usernameController,
            focusNode: usernameFocusNode,
            placeholder: const Text('用户名（可选）'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => onProxyFieldsChanged(),
            onSubmitted: (_) => passwordFocusNode.requestFocus(),
          ),
          const SizedBox(height: 12),
          shadcn.TextField(
            controller: passwordController,
            focusNode: passwordFocusNode,
            placeholder: const Text('密码（可选）'),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onProxyFieldsChanged(),
            onSubmitted: (_) => passwordFocusNode.unfocus(),
          ),
          const SizedBox(height: 12),
          if (proxySummary != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '检测：$proxySummary',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: shadcn.OutlineButton(
              onPressed: isTestingProxy ? null : onTestProxy,
              child:
                  isTestingProxy
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('检测代理'),
            ),
          ),
          if (proxyTestResult != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                proxyTestResult.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      proxyTestResult.success
                          ? Colors.green
                          : theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final proxyHostController = TextEditingController();
    final proxyPortController = TextEditingController();
    final proxyUsernameController = TextEditingController();
    final proxyPasswordController = TextEditingController();
    final hostFocusNode = FocusNode();
    final proxyHostFocusNode = FocusNode();
    final proxyPortFocusNode = FocusNode();
    final proxyUsernameFocusNode = FocusNode();
    final proxyPasswordFocusNode = FocusNode();
    String protocol = 'http';
    var proxyType = _ProxyType.none;
    var isTestingProxy = false;
    _ProxyTestResult? proxyTestResult;

    DialogUtils.showCustomDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => shadcn.AlertDialog(
                  barrierColor: Colors.transparent,
                  surfaceOpacity: 1,
                  title: const Text('添加服务器'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 220,
                      minWidth: 300,
                      maxHeight: 520,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            shadcn.TextField(
                              controller: nameController,
                              placeholder: const Text('名称（如：家里、公司）'),
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => hostFocusNode.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: shadcn.OutlineButton(
                                    onPressed:
                                        () => setDialogState(
                                          () => protocol = 'http',
                                        ),
                                    child: Text(
                                      'HTTP',
                                      style: TextStyle(
                                        fontWeight:
                                            protocol == 'http'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: shadcn.OutlineButton(
                                    onPressed:
                                        () => setDialogState(
                                          () => protocol = 'https',
                                        ),
                                    child: Text(
                                      'HTTPS',
                                      style: TextStyle(
                                        fontWeight:
                                            protocol == 'https'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            shadcn.TextField(
                              controller: hostController,
                              focusNode: hostFocusNode,
                              placeholder: const Text('192.168.1.100:8080'),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              onSubmitted:
                                  (_) =>
                                      proxyType == _ProxyType.none
                                          ? hostFocusNode.unfocus()
                                          : proxyHostFocusNode.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            _buildProxyForm(
                              proxyType: proxyType,
                              onProxyTypeChanged:
                                  (value) => setDialogState(() {
                                    final oldType = proxyType;
                                    final oldPort =
                                        proxyPortController.text.trim();
                                    proxyType = value;
                                    if (value == _ProxyType.none) {
                                      proxyHostController.clear();
                                      proxyPortController.clear();
                                      proxyUsernameController.clear();
                                      proxyPasswordController.clear();
                                    } else if (oldPort.isEmpty ||
                                        oldPort ==
                                            oldType.defaultPort.toString()) {
                                      proxyPortController.text =
                                          value.defaultPort.toString();
                                    }
                                    proxyTestResult = null;
                                  }),
                              onProxyFieldsChanged:
                                  () => setDialogState(
                                    () => proxyTestResult = null,
                                  ),
                              onTestProxy: () async {
                                final host = hostController.text.trim();
                                final serverUrl = '$protocol://$host';
                                final uri = Uri.tryParse(serverUrl);
                                if (host.isEmpty ||
                                    uri == null ||
                                    !uri.hasAuthority) {
                                  DialogUtils.showToast(
                                    context: context,
                                    message: '服务器地址格式不正确',
                                    isError: true,
                                  );
                                  return;
                                }

                                final proxyUrl = _buildProxyUrl(
                                  type: proxyType,
                                  hostController: proxyHostController,
                                  portController: proxyPortController,
                                  usernameController: proxyUsernameController,
                                  passwordController: proxyPasswordController,
                                );
                                if (proxyUrl == null || proxyUrl.isEmpty) {
                                  DialogUtils.showToast(
                                    context: context,
                                    message: '代理配置格式不正确',
                                    isError: true,
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  isTestingProxy = true;
                                  proxyTestResult = null;
                                });
                                final result = await _testProxyConnection(
                                  baseUrl: serverUrl,
                                  proxyUrl: proxyUrl,
                                );
                                if (!context.mounted) return;
                                setDialogState(() {
                                  isTestingProxy = false;
                                  proxyTestResult = result;
                                });
                              },
                              isTestingProxy: isTestingProxy,
                              proxyTestResult: proxyTestResult,
                              hostController: proxyHostController,
                              portController: proxyPortController,
                              usernameController: proxyUsernameController,
                              passwordController: proxyPasswordController,
                              hostFocusNode: proxyHostFocusNode,
                              portFocusNode: proxyPortFocusNode,
                              usernameFocusNode: proxyUsernameFocusNode,
                              passwordFocusNode: proxyPasswordFocusNode,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    shadcn.OutlineButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    shadcn.PrimaryButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final host = hostController.text.trim();
                        if (name.isEmpty || host.isEmpty) {
                          return;
                        }
                        final proxyUrl = _buildProxyUrl(
                          type: proxyType,
                          hostController: proxyHostController,
                          portController: proxyPortController,
                          usernameController: proxyUsernameController,
                          passwordController: proxyPasswordController,
                        );
                        if (proxyUrl == null) {
                          DialogUtils.showToast(
                            context: context,
                            message: '代理地址格式不正确',
                            isError: true,
                          );
                          return;
                        }
                        final url = '$protocol://$host';
                        final uri = Uri.tryParse(url);
                        if (uri == null || !uri.hasAuthority) {
                          return;
                        }
                        await ref
                            .read(serverListProvider.notifier)
                            .addServer(name, url, proxyUrl: proxyUrl);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showEditServerDialog(ServerConfig server) {
    final uri = Uri.tryParse(server.url);
    final proxyData = _parseProxyFormData(server.proxyUrl);
    final nameController = TextEditingController(text: server.name);
    final hostController = TextEditingController(
      text:
          uri != null
              ? '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
              : server.url,
    );
    final proxyHostController = TextEditingController(text: proxyData.host);
    final proxyPortController = TextEditingController(text: proxyData.port);
    final proxyUsernameController = TextEditingController(
      text: proxyData.username,
    );
    final proxyPasswordController = TextEditingController(
      text: proxyData.password,
    );
    final hostFocusNode = FocusNode();
    final proxyHostFocusNode = FocusNode();
    final proxyPortFocusNode = FocusNode();
    final proxyUsernameFocusNode = FocusNode();
    final proxyPasswordFocusNode = FocusNode();
    String protocol = uri?.scheme ?? 'http';
    var proxyType = proxyData.type;
    var isTestingProxy = false;
    _ProxyTestResult? proxyTestResult;

    DialogUtils.showCustomDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => shadcn.AlertDialog(
                  barrierColor: Colors.transparent,
                  surfaceOpacity: 1,
                  title: const Text('编辑服务器'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 300,
                      maxHeight: 520,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            shadcn.TextField(
                              controller: nameController,
                              placeholder: const Text('名称（如：家里、公司）'),
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => hostFocusNode.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: shadcn.OutlineButton(
                                    onPressed:
                                        () => setDialogState(
                                          () => protocol = 'http',
                                        ),
                                    child: Text(
                                      'HTTP',
                                      style: TextStyle(
                                        fontWeight:
                                            protocol == 'http'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: shadcn.OutlineButton(
                                    onPressed:
                                        () => setDialogState(
                                          () => protocol = 'https',
                                        ),
                                    child: Text(
                                      'HTTPS',
                                      style: TextStyle(
                                        fontWeight:
                                            protocol == 'https'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            shadcn.TextField(
                              controller: hostController,
                              focusNode: hostFocusNode,
                              placeholder: const Text('192.168.1.100:8080'),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              onSubmitted:
                                  (_) =>
                                      proxyType == _ProxyType.none
                                          ? hostFocusNode.unfocus()
                                          : proxyHostFocusNode.requestFocus(),
                            ),
                            const SizedBox(height: 12),
                            _buildProxyForm(
                              proxyType: proxyType,
                              onProxyTypeChanged:
                                  (value) => setDialogState(() {
                                    final oldType = proxyType;
                                    final oldPort =
                                        proxyPortController.text.trim();
                                    proxyType = value;
                                    if (value == _ProxyType.none) {
                                      proxyHostController.clear();
                                      proxyPortController.clear();
                                      proxyUsernameController.clear();
                                      proxyPasswordController.clear();
                                    } else if (oldPort.isEmpty ||
                                        oldPort ==
                                            oldType.defaultPort.toString()) {
                                      proxyPortController.text =
                                          value.defaultPort.toString();
                                    }
                                    proxyTestResult = null;
                                  }),
                              onProxyFieldsChanged:
                                  () => setDialogState(
                                    () => proxyTestResult = null,
                                  ),
                              onTestProxy: () async {
                                final host = hostController.text.trim();
                                final serverUrl = '$protocol://$host';
                                final uri = Uri.tryParse(serverUrl);
                                if (host.isEmpty ||
                                    uri == null ||
                                    !uri.hasAuthority) {
                                  DialogUtils.showToast(
                                    context: context,
                                    message: '服务器地址格式不正确',
                                    isError: true,
                                  );
                                  return;
                                }

                                final proxyUrl = _buildProxyUrl(
                                  type: proxyType,
                                  hostController: proxyHostController,
                                  portController: proxyPortController,
                                  usernameController: proxyUsernameController,
                                  passwordController: proxyPasswordController,
                                );
                                if (proxyUrl == null || proxyUrl.isEmpty) {
                                  DialogUtils.showToast(
                                    context: context,
                                    message: '代理配置格式不正确',
                                    isError: true,
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  isTestingProxy = true;
                                  proxyTestResult = null;
                                });
                                final result = await _testProxyConnection(
                                  baseUrl: serverUrl,
                                  proxyUrl: proxyUrl,
                                );
                                if (!context.mounted) return;
                                setDialogState(() {
                                  isTestingProxy = false;
                                  proxyTestResult = result;
                                });
                              },
                              isTestingProxy: isTestingProxy,
                              proxyTestResult: proxyTestResult,
                              hostController: proxyHostController,
                              portController: proxyPortController,
                              usernameController: proxyUsernameController,
                              passwordController: proxyPasswordController,
                              hostFocusNode: proxyHostFocusNode,
                              portFocusNode: proxyPortFocusNode,
                              usernameFocusNode: proxyUsernameFocusNode,
                              passwordFocusNode: proxyPasswordFocusNode,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    shadcn.OutlineButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    shadcn.PrimaryButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final host = hostController.text.trim();
                        if (name.isEmpty || host.isEmpty) {
                          return;
                        }
                        final proxyUrl = _buildProxyUrl(
                          type: proxyType,
                          hostController: proxyHostController,
                          portController: proxyPortController,
                          usernameController: proxyUsernameController,
                          passwordController: proxyPasswordController,
                        );
                        if (proxyUrl == null) {
                          DialogUtils.showToast(
                            context: context,
                            message: '代理地址格式不正确',
                            isError: true,
                          );
                          return;
                        }
                        final url = '$protocol://$host';
                        final newUri = Uri.tryParse(url);
                        if (newUri == null || !newUri.hasAuthority) {
                          return;
                        }
                        await ref
                            .read(serverListProvider.notifier)
                            .updateServer(
                              server.id,
                              name: name,
                              url: url,
                              proxyUrl: proxyUrl,
                            );
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showDeleteConfirm(ServerConfig server) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '删除服务器',
      content: '确定要删除「${server.name}」吗？',
      confirmText: '删除',
      isDestructive: true,
    );
    if (confirmed == true) {
      await ref.read(serverListProvider.notifier).removeServer(server.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverListProvider);
    final servers = serverState.servers;
    final currentId = serverState.currentServerId;
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();

    if (isDesktop) {
      return Scaffold(
        appBar:
            canPop
                ? DesktopAppBar(
                  title: const Text('服务器管理'),
                  onBack: () => context.pop(),
                )
                : const DesktopTitleBar(
                  title: Text('服务器管理'),
                  centerTitle: true,
                ),
        body: _buildDesktopBody(servers, currentId, theme, isDark),
      );
    }

    return _buildMobileLayout(servers, currentId, isDark, canPop);
  }

  Widget _buildDesktopBody(
    List<ServerConfig> servers,
    String? currentId,
    ThemeData theme,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildSectionHeader('操作', theme),
        _buildSettingsCard(
          isDark,
          children: [
            _buildActionTile(
              theme,
              isDark,
              icon: CupertinoIcons.add_circled,
              iconColor: Colors.green,
              title: '添加服务器',
              onTap: _showAddServerDialog,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('服务器列表 (${servers.length})', theme),
        if (servers.isEmpty)
          _buildSettingsCard(
            isDark,
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    '暂无服务器',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          _buildSettingsCard(
            isDark,
            children: [
              for (int i = 0; i < servers.length; i++) ...[
                if (i > 0) _buildDivider(isDark),
                _buildDesktopServerTile(
                  servers[i],
                  servers[i].id == currentId,
                  theme,
                  isDark,
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        color: isDark ? Colors.grey[800] : Colors.grey[200],
      ),
    );
  }

  Widget _buildActionTile(
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopServerTile(
    ServerConfig server,
    bool isCurrent,
    ThemeData theme,
    bool isDark,
  ) {
    final isConnecting = _isConnecting && _connectingServerId == server.id;
    final hasProxy = server.proxyUrl.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isConnecting ? null : () => _connectToServer(server),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      isCurrent
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCurrent
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.desktopcomputer,
                  size: 18,
                  color: isCurrent ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.url,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (hasProxy) ...[
                      const SizedBox(height: 2),
                      Text(
                        '代理：${server.proxyUrl}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isConnecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '当前',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(CupertinoIcons.gear, size: 18),
                  color: Colors.grey,
                  onPressed: () => _showEditServerDialog(server),
                  tooltip: '编辑',
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.delete, size: 18),
                  color: Colors.red,
                  onPressed: () => _showDeleteConfirm(server),
                  tooltip: '删除',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    List<ServerConfig> servers,
    String? currentId,
    bool isDark,
    bool canPop,
  ) {
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Icon(
              CupertinoIcons.play_circle_fill,
              size: 64,
              color: CupertinoTheme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Media Player',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              servers.isEmpty ? '添加服务器开始使用' : '选择或添加服务器',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child:
                  servers.isEmpty
                      ? _buildMobileEmptyState(isDark)
                      : _buildMobileServerList(servers, currentId, isDark),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _showAddServerDialog,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.add, size: 20),
                      SizedBox(width: 8),
                      Text('添加服务器'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          decoration: TextDecoration.none,
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
        ),
        child: Column(
          children: [
            CupertinoNavigationBar(
              middle: const Text('服务器管理'),
              backgroundColor: bgColor.withValues(alpha: 0.9),
              border: null,
              leading:
                  canPop
                      ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(CupertinoIcons.back),
                      )
                      : null,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.desktopcomputer,
            size: 64,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无服务器',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮添加服务器',
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileServerList(
    List<ServerConfig> servers,
    String? currentId,
    bool isDark,
  ) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (int i = 0; i < servers.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Divider(
                      height: 0.5,
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                    ),
                  ),
                _buildMobileServerTile(
                  servers[i],
                  servers[i].id == currentId,
                  isDark,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '左滑删除，长按编辑',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileServerTile(
    ServerConfig server,
    bool isCurrent,
    bool isDark,
  ) {
    final isConnecting = _isConnecting && _connectingServerId == server.id;
    final hasProxy = server.proxyUrl.trim().isNotEmpty;

    return Dismissible(
      key: Key(server.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _showDeleteConfirm(server);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: CupertinoColors.destructiveRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: GestureDetector(
        onLongPress: () => _showEditServerDialog(server),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isConnecting ? null : () => _connectToServer(server),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        isCurrent
                            ? CupertinoColors.activeGreen.withValues(
                              alpha: 0.15,
                            )
                            : CupertinoColors.systemGrey.withValues(
                              alpha: 0.15,
                            ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isCurrent
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.desktopcomputer,
                    size: 18,
                    color:
                        isCurrent
                            ? CupertinoColors.activeGreen
                            : CupertinoColors.systemGrey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color:
                              isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        server.url,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                      if (hasProxy) ...[
                        const SizedBox(height: 2),
                        Text(
                          '代理：${server.proxyUrl}',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isConnecting)
                  const CupertinoActivityIndicator()
                else if (isCurrent)
                  Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.activeGreen.resolveFrom(context),
                    ),
                  )
                else
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
