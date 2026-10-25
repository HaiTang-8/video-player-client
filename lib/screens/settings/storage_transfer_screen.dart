import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/form_page.dart';
import '../../core/widgets/password_text_field.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

const _successColor = Color(0xFF34C759);

Widget _buttonLabel(bool loading, String label) {
  return loading
      ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
      : Text(label);
}

/// 导入存储源页面
class StorageImportScreen extends ConsumerStatefulWidget {
  const StorageImportScreen({super.key});

  @override
  ConsumerState<StorageImportScreen> createState() =>
      _StorageImportScreenState();
}

class _StorageImportScreenState extends ConsumerState<StorageImportScreen> {
  final _dataController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _importing = false;
  String? _error;
  StorageImportResult? _result;

  @override
  void dispose() {
    _dataController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    if (_dataController.text.trim().isEmpty) {
      setState(() => _error = '请粘贴导出的加密数据');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    final password = _passwordController.text;
    final (success, result, error) = await ref
        .read(storagesProvider.notifier)
        .importStorages(
          data: _dataController.text.trim(),
          password: password.isEmpty ? null : password,
        );
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (success && result != null) {
        _result = result;
      } else {
        _error = error ?? '导入失败';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _buildResult(context, result);

    final theme = Theme.of(context);
    return FormPageScaffold(
      title: '导入存储源',
      bottomAction: shadcn.PrimaryButton(
        onPressed: _importing ? null : _handleImport,
        alignment: Alignment.center,
        child: _buttonLabel(_importing, '导入'),
      ),
      children: [
        FormSection(
          title: '导入数据',
          children: [
            FormFieldBlock(
              label: '加密数据',
              helper: '粘贴从“导出”获得的数据，已存在的同名存储源会被跳过',
              child: shadcn.TextField(
                controller: _dataController,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            FormFieldBlock(
              label: '导入密码（可选）',
              helper: '导出时设置过密码才需要填写',
              child: PasswordTextField(
                controller: _passwordController,
                placeholder: const Text('留空使用默认加密'),
              ),
            ),
            if (_error != null)
              FormNotice(
                icon: CupertinoIcons.exclamationmark_circle,
                message: _error!,
                color: theme.colorScheme.error,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, StorageImportResult result) {
    final colors = context.appColors;
    final errors = result.errors ?? const <String>[];
    return FormPageScaffold(
      title: '导入存储源',
      bottomAction: shadcn.PrimaryButton(
        onPressed: () => context.pop(true),
        alignment: Alignment.center,
        child: const Text('完成'),
      ),
      children: [
        FormSection(
          title: '导入结果',
          children: [
            FormNotice(
              icon: CupertinoIcons.checkmark_circle,
              message:
                  '导入完成：成功 ${result.successCount} 个，跳过 ${result.skippedCount} 个',
              color: _successColor,
            ),
            if (result.skippedNames.isNotEmpty)
              FormFieldBlock(
                label: '已存在，已跳过',
                child: _NameList(
                  names: result.skippedNames,
                  color: colors.textSecondary,
                ),
              ),
            if (errors.isNotEmpty)
              FormFieldBlock(
                label: '错误',
                child: _NameList(
                  names: errors,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NameList extends StatelessWidget {
  final List<String> names;
  final Color color;

  const _NameList({required this.names, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in names)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 导出存储源页面
class StorageExportScreen extends ConsumerStatefulWidget {
  const StorageExportScreen({super.key});

  @override
  ConsumerState<StorageExportScreen> createState() =>
      _StorageExportScreenState();
}

class _StorageExportScreenState extends ConsumerState<StorageExportScreen> {
  final _passwordController = TextEditingController();
  bool _exporting = false;
  bool _copied = false;
  String? _error;
  String? _data;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    final password = _passwordController.text;
    final (success, data, error) = await ref
        .read(storagesProvider.notifier)
        .exportStorages(password: password.isEmpty ? null : password);
    if (!mounted) return;
    if (!success || data == null) {
      setState(() {
        _exporting = false;
        _error = error ?? '导出失败';
      });
      return;
    }
    await Clipboard.setData(ClipboardData(text: data));
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _data = data;
      _copied = true;
    });
  }

  Future<void> _copyAgain() async {
    await Clipboard.setData(ClipboardData(text: _data!));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final data = _data;

    return FormPageScaffold(
      title: '导出存储源',
      bottomAction:
          data == null
              ? shadcn.PrimaryButton(
                onPressed: _exporting ? null : _handleExport,
                alignment: Alignment.center,
                child: _buttonLabel(_exporting, '生成并复制'),
              )
              : shadcn.PrimaryButton(
                onPressed: _copyAgain,
                alignment: Alignment.center,
                child: const Text('再次复制'),
              ),
      children: [
        FormSection(
          title: '加密设置',
          children: [
            FormFieldBlock(
              label: '导出密码（可选）',
              helper: '设置后，导入时需要输入相同密码',
              child: PasswordTextField(
                controller: _passwordController,
                placeholder: const Text('留空使用默认加密'),
                onChanged: (_) {
                  if (_data != null || _error != null) {
                    setState(() {
                      _data = null;
                      _copied = false;
                      _error = null;
                    });
                  }
                },
              ),
            ),
            if (_error != null)
              FormNotice(
                icon: CupertinoIcons.exclamationmark_circle,
                message: _error!,
                color: theme.colorScheme.error,
              ),
          ],
        ),
        if (data != null)
          FormSection(
            title: '导出数据',
            children: [
              if (_copied)
                const FormNotice(
                  icon: CupertinoIcons.checkmark_circle,
                  message: '已复制到剪贴板，可在其他设备的“导入”中粘贴',
                  color: _successColor,
                ),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  color: colors.cardBackgroundSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    data,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
