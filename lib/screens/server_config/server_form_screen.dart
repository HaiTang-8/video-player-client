import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/form_page.dart';
import '../../core/widgets/password_text_field.dart';
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

  static _ProxyType fromScheme(String scheme) {
    return _ProxyType.values.firstWhere(
      (type) => type.scheme == scheme,
      orElse: () => _ProxyType.none,
    );
  }
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

  factory _ProxyFormData.parse(String proxyUrl) {
    final value = proxyUrl.trim();
    if (value.isEmpty) return const _ProxyFormData(type: _ProxyType.none);

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) {
      return const _ProxyFormData(type: _ProxyType.none);
    }

    final type = _ProxyType.fromScheme(uri.scheme);
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

/// 添加 / 编辑服务器页面；保存成功后 pop(true)
class ServerFormScreen extends ConsumerStatefulWidget {
  final String? serverId;

  const ServerFormScreen({super.key, this.serverId});

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _proxyUsernameController = TextEditingController();
  final _proxyPasswordController = TextEditingController();
  final _hostFocusNode = FocusNode();
  final _proxyHostFocusNode = FocusNode();
  final _proxyPortFocusNode = FocusNode();
  final _proxyUsernameFocusNode = FocusNode();
  final _proxyPasswordFocusNode = FocusNode();

  ServerConfig? _server;
  String _protocol = 'http';
  var _proxyType = _ProxyType.none;
  bool _isTestingProxy = false;
  bool _isSaving = false;
  _ProxyTestResult? _proxyTestResult;

  bool get _isEditing => widget.serverId != null;

  @override
  void initState() {
    super.initState();
    final server =
        _isEditing
            ? ref
                .read(serverListProvider)
                .servers
                .where((s) => s.id == widget.serverId)
                .firstOrNull
            : null;
    _server = server;
    if (server == null) return;

    final uri = Uri.tryParse(server.url);
    final proxyData = _ProxyFormData.parse(server.proxyUrl);
    _nameController.text = server.name;
    _hostController.text =
        uri != null
            ? '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
            : server.url;
    _protocol = uri?.scheme ?? 'http';
    _proxyType = proxyData.type;
    _proxyHostController.text = proxyData.host;
    _proxyPortController.text = proxyData.port;
    _proxyUsernameController.text = proxyData.username;
    _proxyPasswordController.text = proxyData.password;
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _hostController,
      _proxyHostController,
      _proxyPortController,
      _proxyUsernameController,
      _proxyPasswordController,
    ]) {
      controller.dispose();
    }
    for (final node in [
      _hostFocusNode,
      _proxyHostFocusNode,
      _proxyPortFocusNode,
      _proxyUsernameFocusNode,
      _proxyPasswordFocusNode,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  String get _serverUrl => '$_protocol://${_hostController.text.trim()}';

  bool get _isServerUrlValid {
    if (_hostController.text.trim().isEmpty) return false;
    final uri = Uri.tryParse(_serverUrl);
    return uri != null && uri.hasAuthority;
  }

  /// 返回 null 表示代理配置不合法，'' 表示不使用代理
  String? _buildProxyUrl() {
    final type = _proxyType;
    if (type == _ProxyType.none) return '';

    final host = _proxyHostController.text.trim();
    if (host.isEmpty) return null;

    final portText = _proxyPortController.text.trim();
    final port = portText.isEmpty ? type.defaultPort : int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) return null;

    final username = _proxyUsernameController.text.trim();
    final password = _proxyPasswordController.text;
    if (username.isEmpty && password.isNotEmpty) return null;

    return Uri(
      scheme: type.scheme,
      userInfo: username.isEmpty ? null : '$username:$password',
      host: host,
      port: port,
    ).toString();
  }

  void _showError(String message) {
    DialogUtils.showToast(context: context, message: message, isError: true);
  }

  void _clearProxyResult() {
    if (_proxyTestResult != null) setState(() => _proxyTestResult = null);
  }

  void _onProxyTypeChanged(_ProxyType value) {
    setState(() {
      final oldType = _proxyType;
      final oldPort = _proxyPortController.text.trim();
      _proxyType = value;
      if (value == _ProxyType.none) {
        _proxyHostController.clear();
        _proxyPortController.clear();
        _proxyUsernameController.clear();
        _proxyPasswordController.clear();
      } else if (oldPort.isEmpty || oldPort == oldType.defaultPort.toString()) {
        _proxyPortController.text = value.defaultPort.toString();
      }
      _proxyTestResult = null;
    });
  }

  Future<void> _handleTestProxy() async {
    if (!_isServerUrlValid) {
      _showError('服务器地址格式不正确');
      return;
    }
    final proxyUrl = _buildProxyUrl();
    if (proxyUrl == null || proxyUrl.isEmpty) {
      _showError('代理配置格式不正确');
      return;
    }

    setState(() {
      _isTestingProxy = true;
      _proxyTestResult = null;
    });
    final result = await _testProxyConnection(
      baseUrl: _serverUrl,
      proxyUrl: proxyUrl,
    );
    if (!mounted) return;
    setState(() {
      _isTestingProxy = false;
      _proxyTestResult = result;
    });
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    String? error;
    if (name.isEmpty) {
      error = '请输入服务器名称';
    } else if (_hostController.text.trim().isEmpty) {
      error = '请输入服务器地址';
    } else if (!_isServerUrlValid) {
      error = '服务器地址格式不正确';
    }
    final proxyUrl = _buildProxyUrl();
    if (error == null && proxyUrl == null) {
      error = '代理地址格式不正确';
    }
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(serverListProvider.notifier);
    final server = _server;
    if (server != null) {
      await notifier.updateServer(
        server.id,
        name: name,
        url: _serverUrl,
        proxyUrl: proxyUrl,
      );
    } else {
      await notifier.addServer(name, _serverUrl, proxyUrl: proxyUrl!);
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? '编辑服务器' : '添加服务器';
    final theme = Theme.of(context);

    if (_isEditing && _server == null) {
      return FormPageScaffold(
        title: title,
        children: [
          const SizedBox(height: 16),
          FormNotice(
            icon: CupertinoIcons.exclamationmark_circle,
            message: '找不到该服务器，可能已被删除',
            color: theme.colorScheme.error,
          ),
        ],
      );
    }

    return FormPageScaffold(
      title: title,
      bottomAction: shadcn.PrimaryButton(
        onPressed: _isSaving ? null : _handleSave,
        alignment: Alignment.center,
        child:
            _isSaving
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(_isEditing ? '保存' : '添加'),
      ),
      children: [
        FormSection(
          title: '基本信息',
          children: [
            FormFieldBlock(
              label: '名称',
              child: shadcn.TextField(
                controller: _nameController,
                placeholder: const Text('如：家里、公司'),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _hostFocusNode.requestFocus(),
              ),
            ),
          ],
        ),
        FormSection(
          title: '服务器地址',
          children: [
            FormFieldBlock(label: '协议', child: _buildProtocolSelector()),
            FormFieldBlock(
              label: '地址',
              helper:
                  _hostController.text.trim().isEmpty
                      ? '填写 IP 或域名，可带端口'
                      : '将连接：$_serverUrl',
              child: shadcn.TextField(
                controller: _hostController,
                focusNode: _hostFocusNode,
                placeholder: const Text('192.168.1.100:8080'),
                keyboardType: TextInputType.url,
                textInputAction:
                    _proxyType == _ProxyType.none
                        ? TextInputAction.done
                        : TextInputAction.next,
                onChanged: (_) => setState(() => _proxyTestResult = null),
                onSubmitted:
                    (_) =>
                        _proxyType == _ProxyType.none
                            ? _hostFocusNode.unfocus()
                            : _proxyHostFocusNode.requestFocus(),
              ),
            ),
          ],
        ),
        FormSection(title: '代理', children: _buildProxyFields(theme)),
      ],
    );
  }

  Widget _buildProtocolSelector() {
    final color = Theme.of(context).colorScheme.primary;
    Widget option(String protocol, String label, IconData icon) {
      return Expanded(
        child: FormOptionCard(
          selected: _protocol == protocol,
          color: color,
          onTap: () => setState(() {
            _protocol = protocol;
            _proxyTestResult = null;
          }),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: context.appColors.iconSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        option('http', 'HTTP', CupertinoIcons.globe),
        const SizedBox(width: 8),
        option('https', 'HTTPS', CupertinoIcons.lock),
      ],
    );
  }

  List<Widget> _buildProxyFields(ThemeData theme) {
    final enabled = _proxyType != _ProxyType.none;
    final proxyHost = _proxyHostController.text.trim();
    final proxyPort = _proxyPortController.text.trim();
    final proxySummary =
        enabled && proxyHost.isNotEmpty
            ? '${_proxyType.label} $proxyHost:${proxyPort.isEmpty ? _proxyType.defaultPort : proxyPort}'
            : null;
    final result = _proxyTestResult;

    return [
      FormFieldBlock(
        label: '代理类型',
        helper: enabled ? null : '直连服务器，不经过代理',
        child: SizedBox(
          width: double.infinity,
          child: shadcn.Select<_ProxyType>(
            value: _proxyType,
            itemBuilder: (context, item) => Text(item.label),
            onChanged: (value) {
              if (value != null) _onProxyTypeChanged(value);
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
      ),
      if (enabled) ...[
        FormFieldBlock(
          label: '代理地址',
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: shadcn.TextField(
                  controller: _proxyHostController,
                  focusNode: _proxyHostFocusNode,
                  placeholder: const Text('127.0.0.1'),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _proxyTestResult = null),
                  onSubmitted: (_) => _proxyPortFocusNode.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: shadcn.TextField(
                  controller: _proxyPortController,
                  focusNode: _proxyPortFocusNode,
                  placeholder: Text('${_proxyType.defaultPort}'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _proxyTestResult = null),
                  onSubmitted: (_) => _proxyUsernameFocusNode.requestFocus(),
                ),
              ),
            ],
          ),
        ),
        FormFieldBlock(
          label: '用户名（可选）',
          child: shadcn.TextField(
            controller: _proxyUsernameController,
            focusNode: _proxyUsernameFocusNode,
            placeholder: const Text('用户名'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearProxyResult(),
            onSubmitted: (_) => _proxyPasswordFocusNode.requestFocus(),
          ),
        ),
        FormFieldBlock(
          label: '密码（可选）',
          child: PasswordTextField(
            controller: _proxyPasswordController,
            focusNode: _proxyPasswordFocusNode,
            placeholder: const Text('密码'),
            textInputAction: TextInputAction.done,
            onChanged: (_) => _clearProxyResult(),
            onSubmitted: (_) => _proxyPasswordFocusNode.unfocus(),
          ),
        ),
        FormFieldBlock(
          label: '连通性',
          helper:
              proxySummary == null
                  ? '检测出口 IP 和后端是否可达'
                  : '将通过 $proxySummary 访问服务器',
          child: SizedBox(
            width: double.infinity,
            child: shadcn.OutlineButton(
              onPressed: _isTestingProxy ? null : _handleTestProxy,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isTestingProxy
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(CupertinoIcons.wifi, size: 14),
                  const SizedBox(width: 8),
                  Text(_isTestingProxy ? '检测中...' : '检测代理'),
                ],
              ),
            ),
          ),
        ),
        if (result != null)
          FormNotice(
            icon:
                result.success
                    ? CupertinoIcons.checkmark_circle
                    : CupertinoIcons.exclamationmark_circle,
            message: result.message,
            color:
                result.success
                    ? const Color(0xFF34C759)
                    : theme.colorScheme.error,
          ),
      ],
    ];
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
      final ipMessage =
          ipInfo == null ? '出口 IP：查询失败' : '出口 IP：${ipInfo.displayText}';
      if (backendOk) {
        return _ProxyTestResult(success: true, message: '$ipMessage\n后端连接：正常');
      }
      return _ProxyTestResult(success: false, message: '$ipMessage\n后端连接：失败');
    } on DioException catch (e) {
      return _ProxyTestResult(success: false, message: _proxyDioErrorMessage(e));
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
}
