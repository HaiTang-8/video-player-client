import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/password_text_field.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 存储源类型枚举
enum StorageType {
  webdav('webdav', 'WebDAV', CupertinoIcons.cloud),
  local('local', '本地存储', CupertinoIcons.folder),
  openlist('openlist', 'OpenList', CupertinoIcons.link);

  final String value;
  final String label;
  final IconData icon;

  const StorageType(this.value, this.label, this.icon);

  static StorageType fromString(String value) {
    return StorageType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => StorageType.webdav,
    );
  }
}

/// 存储源管理页面
class StoragesScreen extends ConsumerStatefulWidget {
  const StoragesScreen({super.key});

  @override
  ConsumerState<StoragesScreen> createState() => _StoragesScreenState();
}

class _StoragesScreenState extends ConsumerState<StoragesScreen> {
  // 防止“导出/导入”在短时间内被触发多次（例如 dropdown 关闭动画期间重复触发），
  // 否则会出现：首次点击弹窗闪一下无响应、第二次点击叠两个弹窗、点击确定像“没反应”等问题。
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storagesProvider.notifier).loadStorages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final storagesAsync = ref.watch(storagesProvider);
    final scanState = ref.watch(scanStateProvider);
    final isDesktop = WindowControls.isDesktop;

    final actions = [
      Builder(
        builder:
            (buttonContext) => shadcn.IconButton.ghost(
              icon: const Icon(CupertinoIcons.ellipsis_vertical),
              onPressed: () {
                shadcn.showDropdown(
                  context: buttonContext,
                  builder:
                      (context) => shadcn.DropdownMenu(
                        children: [
                          shadcn.MenuButton(
                            leading: const Icon(
                              CupertinoIcons.square_arrow_up,
                              size: 18,
                            ),
                            child: const Text('导出'),
                            onPressed: (menuContext) {
                              shadcn.closeOverlay(menuContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                unawaited(_exportStorages());
                              });
                            },
                          ),
                          shadcn.MenuButton(
                            leading: const Icon(
                              CupertinoIcons.square_arrow_down,
                              size: 18,
                            ),
                            child: const Text('导入'),
                            onPressed: (menuContext) {
                              shadcn.closeOverlay(menuContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                unawaited(_importStorages());
                              });
                            },
                          ),
                        ],
                      ),
                );
              },
            ),
      ),
    ];

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopAppBar(
                title: const Text('存储源管理'),
                onBack: () => context.pop(),
                actions: actions,
              )
              : MobileAppBar(
                title: const Text('存储源管理'),
                onBack: () => context.pop(),
                actions: actions,
              ),
      body: storagesAsync.when(
        loading: () => const ListSkeletonLoader(),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry: () => ref.read(storagesProvider.notifier).loadStorages(),
            ),
        data: (storages) {
          if (storages.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildStorageList(context, storages, scanState, isDesktop);
        },
      ),
      floatingActionButton: shadcn.PrimaryButton(
        onPressed: () => _showAddStorageDialog(context),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.add, size: 18),
            SizedBox(width: 8),
            Text('添加存储源'),
          ],
        ),
      ),
    );
  }

  Future<void> _exportStorages() async {
    if (_exporting) return;
    _exporting = true;
    try {
      final password = await DialogUtils.showInputDialog(
        context: context,
        title: '导出密码（可选）',
        placeholder: '留空使用默认加密',
        obscureText: true,
      );

      if (password == null || !mounted) return;

      final (success, data, error) = await ref
          .read(storagesProvider.notifier)
          .exportStorages(
            password: password.isEmpty ? null : password,
          );

      if (!success || data == null) {
        if (mounted) {
          DialogUtils.showToast(
            context: context,
            message: error ?? '导出失败',
            isError: true,
          );
        }
        return;
      }

      if (mounted) {
        await Clipboard.setData(ClipboardData(text: data));
        if (!mounted) return;
        DialogUtils.showToast(context: context, message: '已复制到剪贴板');
      }
    } finally {
      _exporting = false;
    }
  }

  Future<void> _importStorages() async {
    if (_importing) return;
    _importing = true;
    try {
      final result = await _showImportDialog();
      if (result == null || result.data.isEmpty || !mounted) return;

      final (success, importResult, error) = await ref
          .read(storagesProvider.notifier)
          .importStorages(
            data: result.data,
            password: result.password.isEmpty ? null : result.password,
          );

      if (!mounted) return;

      if (success && importResult != null) {
        final message =
            '导入成功: ${importResult.successCount}, 跳过: ${importResult.skippedCount}';
        DialogUtils.showToast(context: context, message: message);

        if (importResult.skippedNames.isNotEmpty) {
          await DialogUtils.showConfirmDialog(
            context: context,
            title: '已跳过的存储源',
            content: '以下存储源已存在，已跳过:\n${importResult.skippedNames.join('\n')}',
            confirmText: '确定',
            cancelText: '',
          );
        }
      }
    } finally {
      _importing = false;
    }
  }

  Future<({String data, String password})?> _showImportDialog() async {
    final dataController = TextEditingController();
    final passwordController = TextEditingController();
    var hasData = false;

    return shadcn.showDialog<({String data, String password})>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => shadcn.AlertDialog(
          title: const Text('导入存储源'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Text('加密数据'),
                const SizedBox(height: 8),
                shadcn.TextField(
                  controller: dataController,
                  autofocus: true,
                  maxLines: 3,
                  onChanged: (value) => setState(() => hasData = value.isNotEmpty),
                ),
                const SizedBox(height: 16),
                const Text('导入密码（可选）'),
                const SizedBox(height: 8),
                PasswordTextField(
                  controller: passwordController,
                  placeholder: const Text('留空使用默认加密'),
                ),
              ],
            ),
          ),
          actions: [
            shadcn.OutlineButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            shadcn.PrimaryButton(
              onPressed: hasData
                  ? () => Navigator.pop(
                        context,
                        (data: dataController.text, password: passwordController.text),
                      )
                  : null,
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.folder_badge_plus,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无存储源',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮添加存储源',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageList(
    BuildContext context,
    List<Storage> storages,
    ScanState scanState,
    bool isDesktop,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(storagesProvider.notifier).loadStorages(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount =
              isDesktop && constraints.maxWidth > 800
                  ? (constraints.maxWidth > 1200 ? 3 : 2)
                  : 1;

          if (crossAxisCount == 1) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: storages.length,
              itemBuilder: (context, index) {
                final storage = storages[index];
                return _StorageCard(
                  storage: storage,
                  onEdit: () => _showEditStorageDialog(context, storage),
                  onDelete: () => _deleteStorage(storage),
                  onBrowse:
                      () => context.push(
                        '/storages/${storage.id}',
                        extra: storage,
                      ),
                  onToggleEnabled:
                      (enabled) => _toggleStorageEnabled(storage, enabled),
                );
              },
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
            ),
            itemCount: storages.length,
            itemBuilder: (context, index) {
              final storage = storages[index];
              return _StorageCard(
                storage: storage,
                onEdit: () => _showEditStorageDialog(context, storage),
                onDelete: () => _deleteStorage(storage),
                onBrowse:
                    () =>
                        context.push('/storages/${storage.id}', extra: storage),
                onToggleEnabled:
                    (enabled) => _toggleStorageEnabled(storage, enabled),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteStorage(Storage storage) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '删除存储源',
      content: '确定要删除 "${storage.name}" 吗？',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirmed == true) {
      final success = await ref
          .read(storagesProvider.notifier)
          .deleteStorage(storage.id);
      if (!success && mounted) {
        DialogUtils.showToast(context: context, message: '删除失败', isError: true);
      }
    }
  }

  Future<void> _toggleStorageEnabled(Storage storage, bool enabled) async {
    if (enabled) {
      final success = await ref
          .read(storagesProvider.notifier)
          .enableStorage(storage.id);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '存储源已启用' : '启用失败',
          isError: !success,
        );
      }
    } else {
      final result = await _showDisableOptionsDialog(storage);
      if (result == null) return;
      final success = await ref
          .read(storagesProvider.notifier)
          .disableStorage(storage.id, hideMedia: result);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '存储源已禁用' : '禁用失败',
          isError: !success,
        );
      }
    }
  }

  Future<bool?> _showDisableOptionsDialog(Storage storage) async {
    return shadcn.showDialog<bool>(
      context: context,
      builder:
          (context) => shadcn.AlertDialog(
            title: const Text('禁用存储源'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定要禁用「${storage.name}」吗？'),
                const SizedBox(height: 12),
                Text(
                  '禁用后，该存储源将不再被扫描。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              shadcn.OutlineButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('取消'),
              ),
              shadcn.OutlineButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('仅禁用'),
              ),
              shadcn.PrimaryButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('禁用并隐藏媒体'),
              ),
            ],
          ),
    );
  }

  void _showAddStorageDialog(BuildContext context) {
    shadcn.showDialog(
      context: context,
      builder:
          (context) => _StorageFormDialog(
            onSubmit: (name, type, settings) async {
              final success = await ref
                  .read(storagesProvider.notifier)
                  .addStorage(name: name, type: type, settings: settings);
              if (context.mounted) {
                Navigator.pop(context);
                DialogUtils.showToast(
                  context: context,
                  message: success ? '添加成功' : '添加失败',
                  isError: !success,
                );
              }
            },
          ),
    );
  }

  void _showEditStorageDialog(BuildContext context, Storage storage) {
    shadcn.showDialog(
      context: context,
      builder:
          (context) => _StorageFormDialog(
            storage: storage,
            onSubmit: (name, type, settings) async {
              final success = await ref
                  .read(storagesProvider.notifier)
                  .updateStorage(
                    id: storage.id,
                    name: name,
                    type: type,
                    settings: settings,
                  );
              if (context.mounted) {
                Navigator.pop(context);
                DialogUtils.showToast(
                  context: context,
                  message: success ? '更新成功' : '更新失败',
                  isError: !success,
                );
              }
            },
          ),
    );
  }
}

/// 存储源卡片
class _StorageCard extends StatelessWidget {
  final Storage storage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onBrowse;
  final ValueChanged<bool> onToggleEnabled;

  const _StorageCard({
    required this.storage,
    required this.onEdit,
    required this.onDelete,
    required this.onBrowse,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storageType = StorageType.fromString(storage.type);

    return shadcn.Card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: storage.enabled ? 0.1 : 0.05,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  storageType.icon,
                  color:
                      storage.enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storage.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            storage.enabled ? null : theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildTypeBadge(context, storageType),
                        if (!storage.enabled && storage.hideWhenDisabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '媒体已隐藏',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                        if (storage.settings?['url'] != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              storage.settings!['url']!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: storage.enabled,
                onChanged: onToggleEnabled,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(BuildContext context, StorageType type) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        shadcn.OutlineButton(
          onPressed: onEdit,
          size: shadcn.ButtonSize.small,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.pencil, size: 14),
              SizedBox(width: 6),
              Text('编辑'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        shadcn.OutlineButton(
          onPressed: onDelete,
          size: shadcn.ButtonSize.small,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.trash, size: 14),
              SizedBox(width: 6),
              Text('删除'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        shadcn.PrimaryButton(
          onPressed: onBrowse,
          size: shadcn.ButtonSize.small,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.folder, size: 14),
              SizedBox(width: 6),
              Text('浏览'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 存储源表单对话框
class _StorageFormDialog extends ConsumerStatefulWidget {
  final Storage? storage;
  final Future<void> Function(
    String name,
    String type,
    Map<String, String> settings,
  )
  onSubmit;

  const _StorageFormDialog({this.storage, required this.onSubmit});

  @override
  ConsumerState<_StorageFormDialog> createState() => _StorageFormDialogState();
}

class _StorageFormDialogState extends ConsumerState<_StorageFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _proxyUrlController;
  late final TextEditingController _publicBaseUrlController;
  late final TextEditingController _tokenController;

  late StorageType _selectedType;
  bool _useProxy = false;
  String _streamMode = 'redirect';
  bool _isSubmitting = false;
  bool _isTesting = false;

  bool get isEditing => widget.storage != null;

  @override
  void initState() {
    super.initState();
    final storage = widget.storage;
    final settings = storage?.settings ?? {};

    _nameController = TextEditingController(text: storage?.name ?? '');
    _urlController = TextEditingController(
      text: settings['url'] ?? settings['path'] ?? '',
    );
    _usernameController = TextEditingController(
      text: settings['username'] ?? '',
    );
    _passwordController = TextEditingController(
      text: settings['password'] ?? '',
    );
    _proxyUrlController = TextEditingController(
      text: settings['proxy_url'] ?? '',
    );
    _publicBaseUrlController = TextEditingController(
      text: settings['public_base_url'] ?? '',
    );
    _tokenController = TextEditingController(text: settings['token'] ?? '');

    _selectedType =
        storage != null
            ? StorageType.fromString(storage.type)
            : StorageType.webdav;
    _useProxy = settings['use_proxy'] == 'true';
    _streamMode = settings['stream_mode'] ?? 'redirect';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _proxyUrlController.dispose();
    _publicBaseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = WindowControls.isDesktop;
    final dialogWidth =
        isDesktop ? 480.0 : MediaQuery.of(context).size.width * 0.9;

    return shadcn.AlertDialog(
      title: Text(isEditing ? '编辑存储源' : '添加存储源'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildNameField(),
              const SizedBox(height: 16),
              _buildTypeSelector(),
              const SizedBox(height: 16),
              ..._buildTypeSpecificFields(),
            ],
          ),
        ),
      ),
      actions: [
        shadcn.OutlineButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        shadcn.PrimaryButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child:
              _isSubmitting
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Text(isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('名称').semiBold().small(),
        const SizedBox(height: 8),
        shadcn.TextField(
          controller: _nameController,
          placeholder: const Text('如：我的媒体库'),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('类型').semiBold().small(),
        const SizedBox(height: 8),
        Row(
          children:
              StorageType.values.map((type) {
                final isSelected = _selectedType == type;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: type != StorageType.values.last ? 8 : 0,
                    ),
                    child:
                        isSelected
                            ? shadcn.PrimaryButton(
                              onPressed:
                                  () => setState(() => _selectedType = type),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(type.icon, size: 16),
                                  const SizedBox(width: 6),
                                  Text(type.label),
                                ],
                              ),
                            )
                            : shadcn.OutlineButton(
                              onPressed:
                                  () => setState(() {
                                    _selectedType = type;
                                    _resetTypeDefaults();
                                  }),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(type.icon, size: 16),
                                  const SizedBox(width: 6),
                                  Text(type.label),
                                ],
                              ),
                            ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  void _resetTypeDefaults() {
    setState(() {
      if (_selectedType == StorageType.webdav) {
        _streamMode = 'redirect';
        _publicBaseUrlController.clear();
      } else if (_selectedType == StorageType.local) {
        _streamMode = 'proxy';
      } else if (_selectedType == StorageType.openlist) {
        _streamMode = 'redirect';
      }
    });
  }

  List<Widget> _buildTypeSpecificFields() {
    switch (_selectedType) {
      case StorageType.webdav:
        return _buildWebDAVFields();
      case StorageType.local:
        return _buildLocalFields();
      case StorageType.openlist:
        return _buildOpenListFields();
    }
  }

  List<Widget> _buildWebDAVFields() {
    return [
      _buildFieldLabel('WebDAV URL'),
      shadcn.TextField(
        controller: _urlController,
        placeholder: const Text('https://example.com/dav'),
        keyboardType: TextInputType.url,
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('用户名'),
      shadcn.TextField(
        controller: _usernameController,
        placeholder: const Text('用户名'),
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('密码'),
      shadcn.TextField(
        controller: _passwordController,
        placeholder: const Text('密码'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      _buildProxySwitch(),
      if (_useProxy) ...[
        const SizedBox(height: 16),
        _buildFieldLabel('代理地址'),
        shadcn.TextField(
          controller: _proxyUrlController,
          placeholder: const Text('代理地址（可选）'),
          keyboardType: TextInputType.url,
        ),
      ],
      const SizedBox(height: 16),
      _buildStreamModeSelector(),
    ];
  }

  List<Widget> _buildLocalFields() {
    return [
      _buildFieldLabel('路径'),
      shadcn.TextField(
        controller: _urlController,
        placeholder: const Text('/path/to/media'),
      ),
      const SizedBox(height: 16),
      _buildStreamModeSelector(),
      if (_streamMode == 'redirect') ...[
        const SizedBox(height: 16),
        _buildFieldLabel('直连基地址'),
        shadcn.TextField(
          controller: _publicBaseUrlController,
          placeholder: const Text('http://nas.local:8081/media'),
          keyboardType: TextInputType.url,
        ),
      ],
    ];
  }

  List<Widget> _buildOpenListFields() {
    return [
      _buildFieldLabel('OpenList 地址'),
      shadcn.TextField(
        controller: _urlController,
        placeholder: const Text('https://openlist.example.com'),
        keyboardType: TextInputType.url,
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('Token（可选）'),
      shadcn.TextField(
        controller: _tokenController,
        placeholder: const Text('访问令牌'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('用户名（可选）'),
      shadcn.TextField(
        controller: _usernameController,
        placeholder: const Text('用户名'),
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('密码（可选）'),
      shadcn.TextField(
        controller: _passwordController,
        placeholder: const Text('密码'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      _buildStreamModeSelector(),
      const SizedBox(height: 16),
      _buildTestConnectionButton(),
    ];
  }

  Widget _buildTestConnectionButton() {
    return shadcn.OutlineButton(
      onPressed: _isTesting ? null : _handleTestConnection,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isTesting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(CupertinoIcons.wifi, size: 14),
          const SizedBox(width: 6),
          Text(_isTesting ? '测试中...' : '测试连接'),
        ],
      ),
    );
  }

  Future<void> _handleTestConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      DialogUtils.showToast(
        context: context,
        message: '请输入 OpenList 地址',
        isError: true,
      );
      return;
    }

    setState(() => _isTesting = true);

    final settings = <String, String>{'url': url, 'stream_mode': _streamMode};
    final token = _tokenController.text.trim();
    if (token.isNotEmpty) {
      settings['token'] = token;
    }
    final username = _usernameController.text.trim();
    if (username.isNotEmpty) {
      settings['username'] = username;
    }
    final password = _passwordController.text;
    if (password.isNotEmpty) {
      settings['password'] = password;
    }

    final (success, error) = await ref
        .read(storagesProvider.notifier)
        .testConnection(type: 'openlist', settings: settings);

    if (mounted) {
      setState(() => _isTesting = false);
      DialogUtils.showToast(
        context: context,
        message: success ? '连接成功' : (error ?? '连接失败'),
        isError: !success,
      );
    }
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label).semiBold().small(),
    );
  }

  Widget _buildProxySwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('使用代理访问').small(),
        shadcn.Switch(
          value: _useProxy,
          onChanged: (value) {
            setState(() {
              _useProxy = value;
              if (!_useProxy) {
                _proxyUrlController.clear();
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildStreamModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('流媒体模式').semiBold().small(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child:
                  _streamMode == 'proxy'
                      ? shadcn.PrimaryButton(
                        onPressed: () => setState(() => _streamMode = 'proxy'),
                        child: const Text('代理'),
                      )
                      : shadcn.OutlineButton(
                        onPressed: () => setState(() => _streamMode = 'proxy'),
                        child: const Text('代理'),
                      ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child:
                  _streamMode == 'redirect'
                      ? shadcn.PrimaryButton(
                        onPressed:
                            () => setState(() => _streamMode = 'redirect'),
                        child: const Text('直连'),
                      )
                      : shadcn.OutlineButton(
                        onPressed:
                            () => setState(() => _streamMode = 'redirect'),
                        child: const Text('直连'),
                      ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      DialogUtils.showToast(context: context, message: '请输入名称', isError: true);
      return;
    }

    Map<String, String> settings;
    switch (_selectedType) {
      case StorageType.webdav:
        settings = {
          'url': _urlController.text.trim(),
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'use_proxy': _useProxy.toString(),
          'stream_mode': _streamMode,
        };
        final proxyUrl = _proxyUrlController.text.trim();
        if (proxyUrl.isNotEmpty) {
          settings['proxy_url'] = proxyUrl;
        }
        break;
      case StorageType.local:
        if (_streamMode == 'redirect' &&
            _publicBaseUrlController.text.trim().isEmpty) {
          DialogUtils.showToast(
            context: context,
            message: '直连模式需要填写直连基地址',
            isError: true,
          );
          return;
        }
        settings = {
          'path': _urlController.text.trim(),
          'stream_mode': _streamMode,
        };
        final publicBaseUrl = _publicBaseUrlController.text.trim();
        if (publicBaseUrl.isNotEmpty) {
          settings['public_base_url'] = publicBaseUrl;
        }
        break;
      case StorageType.openlist:
        settings = {
          'url': _urlController.text.trim(),
          'stream_mode': _streamMode,
        };
        final token = _tokenController.text.trim();
        if (token.isNotEmpty) {
          settings['token'] = token;
        }
        final username = _usernameController.text.trim();
        if (username.isNotEmpty) {
          settings['username'] = username;
        }
        final password = _passwordController.text;
        if (password.isNotEmpty) {
          settings['password'] = password;
        }
        break;
    }

    setState(() => _isSubmitting = true);
    await widget.onSubmit(name, _selectedType.value, settings);
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }
}

extension on Text {
  Widget semiBold() {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w600),
      child: this,
    );
  }

  Widget small() {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 13),
      child: this,
    );
  }
}
