import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/form_page.dart';
import '../../core/widgets/password_text_field.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'driver_fields_form.dart';
import 'storage_type.dart';


/// 添加 / 编辑存储源页面；保存成功后 pop(true)
class StorageFormScreen extends ConsumerStatefulWidget {
  final int? storageId;
  final Storage? storage;

  const StorageFormScreen({super.key, this.storageId, this.storage});

  @override
  ConsumerState<StorageFormScreen> createState() => _StorageFormScreenState();
}

class _StorageFormScreenState extends ConsumerState<StorageFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _proxyUrlController;
  late final TextEditingController _publicBaseUrlController;
  late final TextEditingController _tokenController;

  Storage? _storage;
  late StorageType _selectedType;
  bool _useProxy = false;
  String _streamMode = 'redirect';
  bool _isSubmitting = false;
  bool _isTesting = false;
  final Map<String, DriverFieldsController> _driverFields = {};

  bool get _isEditing => widget.storageId != null;

  /// 按声明渲染时使用的类型：未知类型沿用存储源原始类型
  String get _declaredType =>
      _selectedType == StorageType.unknown
          ? (_storage?.type.trim().toLowerCase() ?? '')
          : _selectedType.value;

  @override
  void initState() {
    super.initState();
    _storage =
        widget.storage ??
        ref
            .read(storagesProvider)
            .value
            ?.where((s) => s.id == widget.storageId)
            .firstOrNull;
    final storage = _storage;
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
    for (final c in _driverFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? '编辑存储源' : '添加存储源';

    if (_isEditing && _storage == null) {
      return FormPageScaffold(
        title: title,
        children: [
          const SizedBox(height: 16),
          FormNotice(
            icon: CupertinoIcons.exclamationmark_circle,
            message: '找不到该存储源，可能已被删除',
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      );
    }

    final drivers =
        _selectedType.hasHandwrittenForm
            ? null
            : ref.watch(storageDriversProvider);
    final meta =
        drivers == null
            ? null
            : DriverMeta.find(drivers.value ?? const [], _declaredType);
    final canSubmit = drivers == null || meta != null;
    final streamModes =
        drivers == null ? null : meta?.capabilities.streamModes ?? const [];

    return FormPageScaffold(
      title: title,
      bottomAction: shadcn.PrimaryButton(
        onPressed:
            _isSubmitting || !canSubmit ? null : () => _handleSubmit(meta),
        alignment: Alignment.center,
        child:
            _isSubmitting
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(_isEditing ? '保存' : '添加'),
      ),
      children: [
        FormSection(title: '类型', children: [_buildTypeSelector()]),
        FormSection(
          title: '基本信息',
          children: [
            FormFieldBlock(
              label: '名称',
              child: shadcn.TextField(
                controller: _nameController,
                placeholder: const Text('如：我的媒体库'),
              ),
            ),
          ],
        ),
        FormSection(
          title: '连接',
          children:
              drivers == null
                  ? _buildConnectionFields()
                  : _buildDeclaredFields(drivers, meta),
        ),
        if (streamModes == null)
          FormSection(title: '播放', children: _buildPlaybackFields())
        else if (streamModes.isNotEmpty)
          FormSection(
            title: '播放',
            children: [
              FormFieldBlock(
                label: '流媒体模式',
                child: _buildStreamModeSelector(streamModes),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    final types =
        _selectedType == StorageType.unknown
            ? const [StorageType.unknown]
            : StorageType.selectable;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final perRow =
            types.length > 2 && constraints.maxWidth < types.length * 96
                ? 2
                : types.length;
        final rows = [
          for (var i = 0; i < types.length; i += perRow)
            types.sublist(i, (i + perRow).clamp(0, types.length)),
        ];
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              Row(
                children: [
                  for (var i = 0; i < perRow; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(
                      child:
                          i < rows[r].length
                              ? _buildTypeCard(rows[r][i])
                              : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTypeCard(StorageType type) {
    final label =
        type == StorageType.unknown
            ? (_storage?.type.isNotEmpty == true ? _storage!.type : type.label)
            : type.label;
    return FormOptionCard(
      selected: _selectedType == type,
      color: type.color,
      onTap: () {
        if (type == _selectedType) return;
        setState(() {
          _selectedType = type;
          _resetTypeDefaults();
        });
      },
      child: Column(
        children: [
          Icon(type.icon, size: 22, color: type.color),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _resetTypeDefaults() {
    if (_selectedType == StorageType.webdav) {
      _streamMode = 'redirect';
      _publicBaseUrlController.clear();
    } else if (_selectedType == StorageType.local) {
      _streamMode = 'proxy';
    } else if (_selectedType == StorageType.openlist) {
      _streamMode = 'redirect';
    }
  }

  List<Widget> _buildConnectionFields() {
    switch (_selectedType) {
      case StorageType.webdav:
        return [
          FormFieldBlock(
            label: 'WebDAV URL',
            child: shadcn.TextField(
              controller: _urlController,
              placeholder: const Text('https://example.com/dav'),
              keyboardType: TextInputType.url,
            ),
          ),
          FormFieldBlock(
            label: '用户名',
            child: shadcn.TextField(
              controller: _usernameController,
              placeholder: const Text('用户名'),
            ),
          ),
          FormFieldBlock(
            label: '密码',
            child: PasswordTextField(
              controller: _passwordController,
              placeholder: const Text('密码'),
            ),
          ),
        ];
      case StorageType.local:
        return [
          FormFieldBlock(
            label: '路径',
            helper: '服务器上的媒体目录',
            child: shadcn.TextField(
              controller: _urlController,
              placeholder: const Text('/path/to/media'),
            ),
          ),
        ];
      case StorageType.openlist:
        return [
          FormFieldBlock(
            label: 'OpenList 地址',
            child: shadcn.TextField(
              controller: _urlController,
              placeholder: const Text('https://openlist.example.com'),
              keyboardType: TextInputType.url,
            ),
          ),
          FormFieldBlock(
            label: 'Token（可选）',
            child: PasswordTextField(
              controller: _tokenController,
              placeholder: const Text('访问令牌'),
            ),
          ),
          FormFieldBlock(
            label: '用户名（可选）',
            child: shadcn.TextField(
              controller: _usernameController,
              placeholder: const Text('用户名'),
            ),
          ),
          FormFieldBlock(
            label: '密码（可选）',
            child: PasswordTextField(
              controller: _passwordController,
              placeholder: const Text('密码'),
            ),
          ),
          _buildTestConnectionButton(_handleTestConnection),
        ];
      case StorageType.quark:
      case StorageType.unknown:
        return const [];
    }
  }

  DriverFieldsController _driverFieldsFor(DriverMeta meta) {
    return _driverFields.putIfAbsent(meta.type, () {
      final storage = _storage;
      final sameType =
          storage != null &&
          storage.type.trim().toLowerCase() == meta.type.toLowerCase();
      return DriverFieldsController(meta, sameType ? storage.settings : null);
    });
  }

  List<Widget> _buildDeclaredFields(
    AsyncValue<List<DriverMeta>> drivers,
    DriverMeta? meta,
  ) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (meta != null) {
      if (meta.fields.isEmpty) {
        return [
          FormNotice(
            icon: CupertinoIcons.info_circle,
            message: '${meta.label}无需额外配置',
            color: context.appColors.textSecondary,
          ),
        ];
      }
      final controller = _driverFieldsFor(meta);
      return [
        DriverFieldsForm(controller: controller),
        _buildTestConnectionButton(() => _handleDeclaredTest(controller)),
      ];
    }
    if (drivers.isLoading) {
      return [
        SkeletonShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                const SkeletonBox(width: 72, height: 14),
                const SizedBox(height: 8),
                SkeletonBox(height: i == 0 ? 72 : 36),
              ],
            ],
          ),
        ),
      ];
    }
    if (drivers.hasError) {
      return [
        FormNotice(
          icon: CupertinoIcons.exclamationmark_circle,
          message: '加载配置项失败：${drivers.error}',
          color: errorColor,
        ),
        shadcn.OutlineButton(
          onPressed: () => ref.invalidate(storageDriversProvider),
          leading: const Icon(CupertinoIcons.refresh, size: 14),
          child: const Text('重试'),
        ),
      ];
    }
    return [
      FormNotice(
        icon: CupertinoIcons.exclamationmark_circle,
        message:
            _selectedType == StorageType.unknown
                ? '当前客户端不支持类型「$_declaredType」，只能查看，请在新版客户端或 Web 后台中编辑'
                : '服务器未提供「${_selectedType.label}」的配置项，请升级服务端',
        color: errorColor,
      ),
    ];
  }

  List<Widget> _buildPlaybackFields() {
    return [
      FormFieldBlock(label: '流媒体模式', child: _buildStreamModeSelector()),
      if (_selectedType == StorageType.webdav) ...[
        _buildProxySwitch(),
        if (_useProxy)
          FormFieldBlock(
            label: '代理地址',
            child: shadcn.TextField(
              controller: _proxyUrlController,
              placeholder: const Text('代理地址（可选）'),
              keyboardType: TextInputType.url,
            ),
          ),
      ],
      if (_selectedType == StorageType.local && _streamMode == 'redirect')
        FormFieldBlock(
          label: '直连基地址',
          helper: '直连模式下客户端访问媒体文件的地址',
          child: shadcn.TextField(
            controller: _publicBaseUrlController,
            placeholder: const Text('http://nas.local:8081/media'),
            keyboardType: TextInputType.url,
          ),
        ),
    ];
  }

  Widget _buildStreamModeSelector([
    List<String> modes = const ['redirect', 'proxy'],
  ]) {
    if (!modes.contains(_streamMode)) _streamMode = modes.first;
    Widget option(String mode, String title, String subtitle) {
      final colors = context.appColors;
      final selected = _streamMode == mode;
      return Expanded(
        child: FormOptionCard(
          selected: selected,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => setState(() => _streamMode = mode),
          alignment: CrossAxisAlignment.start,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < modes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            switch (modes[i]) {
              'redirect' => option(
                'redirect',
                '直连',
                '客户端直接访问存储，速度更快',
              ),
              'proxy' => option('proxy', '代理', '经服务器中转，兼容性更好'),
              final mode => option(mode, mode, ''),
            },
          ],
        ],
      ),
    );
  }

  Widget _buildProxySwitch() {
    return Row(
      children: [
        Expanded(
          child: Text(
            '使用代理访问',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appColors.textPrimary,
            ),
          ),
        ),
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

  Widget _buildTestConnectionButton(VoidCallback onPressed) {
    return shadcn.OutlineButton(
      onPressed: _isTesting ? null : onPressed,
      leading:
          _isTesting
              ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(CupertinoIcons.wifi, size: 14),
      child: Text(_isTesting ? '测试中...' : '测试连接'),
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

  Future<void> _handleDeclaredTest(DriverFieldsController controller) async {
    final error = controller.validate();
    if (error != null) {
      DialogUtils.showToast(context: context, message: error, isError: true);
      return;
    }
    setState(() => _isTesting = true);
    final (success, message) = await ref
        .read(storagesProvider.notifier)
        .testConnection(
          type: controller.meta.type,
          settings: _declaredSettings(controller),
        );
    if (!mounted) return;
    setState(() => _isTesting = false);
    DialogUtils.showToast(
      context: context,
      message: success ? '连接成功' : (message ?? '连接失败'),
      isError: !success,
    );
  }

  Map<String, String> _declaredSettings(DriverFieldsController controller) {
    final settings = controller.values();
    if (controller.meta.capabilities.streamModes.isNotEmpty) {
      settings['stream_mode'] = _streamMode;
    }
    return settings;
  }

  Future<void> _handleSubmit(DriverMeta? meta) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      DialogUtils.showToast(context: context, message: '请输入名称', isError: true);
      return;
    }

    Map<String, String> settings;
    var type = _selectedType.value;
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
      case StorageType.quark:
      case StorageType.unknown:
        if (meta == null) return;
        final controller = _driverFieldsFor(meta);
        final error = controller.validate();
        if (error != null) {
          DialogUtils.showToast(
            context: context,
            message: error,
            isError: true,
          );
          return;
        }
        settings = _declaredSettings(controller);
        type = meta.type;
    }

    setState(() => _isSubmitting = true);
    final notifier = ref.read(storagesProvider.notifier);
    final storage = _storage;
    final success =
        storage != null
            ? await notifier.updateStorage(
              id: storage.id,
              name: name,
              type: type,
              settings: settings,
            )
            : await notifier.addStorage(
              name: name,
              type: type,
              settings: settings,
            );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (success) {
      context.pop(true);
    } else {
      DialogUtils.showToast(
        context: context,
        message: _isEditing ? '更新失败' : '添加失败',
        isError: true,
      );
    }
  }
}
