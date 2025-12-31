import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
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
    } else {
      IosUiUtils.showToast(context: context, message: '无法连接到服务器', isError: true);
    }

    setState(() {
      _isConnecting = false;
      _connectingServerId = null;
    });
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    String protocol = 'http';

    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => CupertinoAlertDialog(
          title: const Text('添加服务器'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoTextField(
                  controller: nameController,
                  placeholder: '名称（如：家里、公司）',
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: protocol,
                    children: const {
                      'http': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('HTTP'),
                      ),
                      'https': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('HTTPS'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        setDialogState(() => protocol = value);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: hostController,
                  placeholder: '192.168.1.100:8080',
                  keyboardType: TextInputType.url,
                  padding: const EdgeInsets.all(12),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
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

  void _showDeleteConfirm(ServerConfig server) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除「${server.name}」吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              await ref.read(serverListProvider.notifier).removeServer(server.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverListProvider);
    final servers = serverState.servers;
    final currentId = serverState.currentServerId;
    final isDesktop = WindowControls.isDesktop;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final canPop = Navigator.of(context).canPop();

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
                  ? _buildEmptyState(context, isDark)
                  : _buildServerList(servers, currentId, isDark),
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

    if (isDesktop) {
      return CupertinoPageScaffold(
        backgroundColor: bgColor,
        child: DefaultTextStyle(
          style: TextStyle(
            decoration: TextDecoration.none,
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
          child: Column(
            children: [
              const DesktopTitleBar(title: Text('服务器管理'), centerTitle: true),
              Expanded(child: SafeArea(top: false, child: content)),
            ],
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: DefaultTextStyle(
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

  Widget _buildEmptyState(BuildContext context, bool isDark) {
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
              fontWeight: FontWeight.w600,
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

  Widget _buildServerList(List<ServerConfig> servers, String? currentId, bool isDark) {
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
                _buildServerTile(servers[i], servers[i].id == currentId, isDark),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '左滑可删除服务器',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServerTile(ServerConfig server, bool isCurrent, bool isDark) {
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
                  isCurrent ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.desktopcomputer,
                  size: 18,
                  color: isCurrent ? CupertinoColors.activeGreen : CupertinoColors.systemGrey,
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
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
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
    );
  }
}
