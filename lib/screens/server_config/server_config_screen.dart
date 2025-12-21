import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

/// 服务器配置页面
class ServerConfigScreen extends ConsumerStatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  ConsumerState<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends ConsumerState<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 如果已有保存的服务器地址，填充到输入框
    final savedUrl = ref.read(serverUrlProvider);
    if (savedUrl != null) {
      _urlController.text = savedUrl;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final url = _urlController.text.trim();
    final connectionNotifier = ref.read(serverConnectionProvider.notifier);
    final success = await connectionNotifier.testConnection(url);

    // 检查 widget 是否还在树中
    if (!mounted) return;

    if (success) {
      // 保存服务器地址
      await ref.read(serverUrlProvider.notifier).setServerUrl(url);
      // 连接成功后页面会跳转，不需要再 setState
      return;
    }

    setState(() {
      _errorMessage = '无法连接到服务器，请检查地址是否正确';
      _isConnecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = ref.watch(serverConnectionProvider);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? const DesktopTitleBar(
              title: Text('Media Player'),
              centerTitle: true,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo 和标题
                    Icon(
                      Icons.play_circle_filled,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Media Player',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '连接到您的媒体服务器',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // 服务器地址输入
                    TextFormField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: 'http://192.168.1.100:8080',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      enabled: !_isConnecting,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入服务器地址';
                        }
                        final uri = Uri.tryParse(value);
                        if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                          return '请输入有效的服务器地址';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _connect(),
                    ),
                    const SizedBox(height: 16),

                    // 错误提示
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 连接按钮
                    FilledButton(
                      onPressed: _isConnecting ? null : _connect,
                      child: _isConnecting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('连接'),
                    ),
                    const SizedBox(height: 24),

                    // 连接状态
                    if (connectionState == ServerConnectionState.connected)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '已连接',
                              style: TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 48),

                    // 帮助文本
                    Text(
                      '请确保您的媒体服务器正在运行，\n并且设备与服务器在同一网络中。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
