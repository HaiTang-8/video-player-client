import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/server_config.dart';
import '../../providers/providers.dart';

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
    final success = await connectionNotifier.testConnection(server.url);

    if (!mounted) return;

    if (success) {
      await ref.read(serverListProvider.notifier).setCurrentServer(server.id);
      ref.read(authProvider.notifier).checkAuthStatus();
    } else {
      DialogUtils.showToast(context: context, message: '无法连接到服务器', isError: true);
    }

    setState(() {
      _isConnecting = false;
      _connectingServerId = null;
    });
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final hostFocusNode = FocusNode();
    String protocol = 'http';

    DialogUtils.showCustomDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => shadcn.AlertDialog(
          barrierColor: Colors.transparent,
          surfaceOpacity: 1,
          title: const Text('添加服务器'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 160, minWidth: 300),
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
                          onPressed: () => setDialogState(() => protocol = 'http'),
                          child: Text(
                            'HTTP',
                            style: TextStyle(
                              fontWeight: protocol == 'http' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: shadcn.OutlineButton(
                          onPressed: () => setDialogState(() => protocol = 'https'),
                          child: Text(
                            'HTTPS',
                            style: TextStyle(
                              fontWeight: protocol == 'https' ? FontWeight.bold : FontWeight.normal,
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
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => hostFocusNode.unfocus(),
                  ),
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
              onPressed: () async {
                final name = nameController.text.trim();
                final host = hostController.text.trim();
                if (name.isEmpty || host.isEmpty) {
                  return;
                }
                final url = '$protocol://$host';
                final uri = Uri.tryParse(url);
                if (uri == null || !uri.hasAuthority) {
                  return;
                }
                await ref.read(serverListProvider.notifier).addServer(name, url);
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
    final nameController = TextEditingController(text: server.name);
    final hostController = TextEditingController(
      text: uri != null ? '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}' : server.url,
    );
    final hostFocusNode = FocusNode();
    String protocol = uri?.scheme ?? 'http';

    DialogUtils.showCustomDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => shadcn.AlertDialog(
          barrierColor: Colors.transparent,
          surfaceOpacity: 1,
          title: const Text('编辑服务器'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 300),
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
                          onPressed: () => setDialogState(() => protocol = 'http'),
                          child: Text(
                            'HTTP',
                            style: TextStyle(
                              fontWeight: protocol == 'http' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: shadcn.OutlineButton(
                          onPressed: () => setDialogState(() => protocol = 'https'),
                          child: Text(
                            'HTTPS',
                            style: TextStyle(
                              fontWeight: protocol == 'https' ? FontWeight.bold : FontWeight.normal,
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
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => hostFocusNode.unfocus(),
                  ),
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
              onPressed: () async {
                final name = nameController.text.trim();
                final host = hostController.text.trim();
                if (name.isEmpty || host.isEmpty) {
                  return;
                }
                final url = '$protocol://$host';
                final newUri = Uri.tryParse(url);
                if (newUri == null || !newUri.hasAuthority) {
                  return;
                }
                await ref.read(serverListProvider.notifier).updateServer(
                  server.id,
                  name: name,
                  url: url,
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
        appBar: canPop
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
                  color: isCurrent
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
              child: servers.isEmpty
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
              leading: canPop
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
                  color: isCurrent
                      ? CupertinoColors.activeGreen.withValues(alpha: 0.15)
                      : CupertinoColors.systemGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCurrent
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.desktopcomputer,
                  size: 18,
                  color: isCurrent
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
                            isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.url,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
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
