import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/password_text_field.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _handleSetup() async {
    _dismissKeyboard();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || password.isEmpty) {
      DialogUtils.showToast(
        context: context,
        message: '请输入用户名和密码',
        isError: true,
      );
      return;
    }

    if (password != confirmPassword) {
      DialogUtils.showToast(
        context: context,
        message: '两次输入的密码不一致',
        isError: true,
      );
      return;
    }

    if (password.length < 6) {
      DialogUtils.showToast(
        context: context,
        message: '密码长度不能少于6位',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).setup(username, password);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = WindowControls.isDesktop;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isDesktop) {
      return Scaffold(
        appBar: const DesktopTitleBar(title: Text('初始设置'), centerTitle: true),
        body: Center(child: _buildForm(isDark)),
      );
    }

    return _buildMobileLayout(isDark);
  }

  Widget _buildMobileLayout(bool isDark) {
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

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
              middle: const Text('初始设置'),
              backgroundColor: bgColor.withValues(alpha: 0.9),
              border: null,
            ),
            Expanded(child: Center(child: _buildForm(isDark))),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        32,
        0,
        32,
        MediaQuery.viewInsetsOf(context).bottom + 32,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
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
                '创建管理员账户以开始使用',
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 40),
              shadcn.TextField(
                controller: _usernameController,
                placeholder: const Text('用户名'),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                autocorrect: false,
                enableSuggestions: false,
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) => _passwordFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordTextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                placeholder: const Text('密码'),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) => _confirmFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmFocusNode,
                placeholder: const Text('确认密码'),
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) => _handleSetup(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _isLoading ? null : _handleSetup,
                  child:
                      _isLoading
                          ? const CupertinoActivityIndicator(
                            color: CupertinoColors.white,
                          )
                          : const Text('创建账户'),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
