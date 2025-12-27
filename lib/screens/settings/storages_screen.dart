import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 存储源管理页面
class StoragesScreen extends ConsumerStatefulWidget {
  const StoragesScreen({super.key});

  @override
  ConsumerState<StoragesScreen> createState() => _StoragesScreenState();
}

class _StoragesScreenState extends ConsumerState<StoragesScreen> {
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

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopTitleBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                // 与影视详情页保持一致：返回按钮使用“<”样式，标题靠左（不居中）
                centerTitle: false,
                leading: AppBackButton(onPressed: () => context.pop()),
                title: const Text('存储源管理'),
              )
              : AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                toolbarHeight: 44,
                // 与影视详情页保持一致：返回按钮使用“<”样式，标题靠左（避免 iOS 默认居中）
                centerTitle: false,
                automaticallyImplyLeading: false,
                leadingWidth: kAppBackButtonWidth,
                titleSpacing: 1,
                leading: AppBackButton(
                  onPressed: () => context.pop(),
                  color: Colors.black,
                ),
                title: const Text(
                  '存储源管理',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      body: storagesAsync.when(
        loading: () => const LoadingWidget(message: '加载中...'),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry: () => ref.read(storagesProvider.notifier).loadStorages(),
            ),
        data: (storages) {
          if (storages.isEmpty) {
            return const EmptyWidget(
              message: '暂无存储源\n点击右下角按钮添加',
              icon: Icons.storage_outlined,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(storagesProvider.notifier).loadStorages(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: storages.length,
              itemBuilder: (context, index) {
                final storage = storages[index];
                final isScanning = scanState.scanning.contains(storage.id);
                final progress = scanState.progresses[storage.id];

                return _StorageCard(
                  storage: storage,
                  isScanning: isScanning,
                  progress: progress,
                  onScan: () => _startScan(storage.id, forceScrape: false),
                  onForceScrape: () => _startScan(storage.id, forceScrape: true),
                  onDelete: () => _deleteStorage(storage),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddStorageDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _startScan(int storageId, {bool forceScrape = false}) async {
    final success = await ref
        .read(scanStateProvider.notifier)
        .startScan(storageId, forceScrape: forceScrape);
    if (!success && mounted) {
      IosUiUtils.showToast(context: context, message: '启动扫描失败', isError: true);
    }
  }

  Future<void> _deleteStorage(Storage storage) async {
    final confirmed = await IosUiUtils.showConfirmDialog(
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
        IosUiUtils.showToast(context: context, message: '删除失败', isError: true);
      }
    }
  }

  void _showAddStorageDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final proxyUrlController = TextEditingController();
    String selectedType = 'webdav';
    bool useProxy = false;

    showCupertinoDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: const Text('添加存储源'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: nameController,
                    placeholder: '名称（如：我的媒体库）',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: CupertinoColors.tertiarySystemFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: selectedType,
                      children: const {
                        'webdav': Text('WebDAV'),
                        'local': Text('本地存储'),
                      },
                      onValueChanged: (value) {
                        setState(() {
                          selectedType = value!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedType == 'webdav') ...[
                    CupertinoTextField(
                      controller: urlController,
                      placeholder: 'WebDAV URL',
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: usernameController,
                      placeholder: '用户名',
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: passwordController,
                      placeholder: '密码',
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('使用代理访问', style: TextStyle(fontSize: 14)),
                        CupertinoSwitch(
                          value: useProxy,
                          onChanged: (value) {
                            setState(() {
                              useProxy = value;
                              if (!useProxy) {
                                proxyUrlController.clear();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (useProxy) ...[
                      const SizedBox(height: 8),
                      CupertinoTextField(
                        controller: proxyUrlController,
                        placeholder: '代理地址（可选）',
                        keyboardType: TextInputType.url,
                      ),
                    ],
                  ] else ...[
                    CupertinoTextField(
                      controller: urlController,
                      placeholder: '路径（如：/path/to/media）',
                    ),
                  ],
                ],
              ),
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
                if (name.isEmpty) {
                  IosUiUtils.showToast(context: context, message: '请输入名称', isError: true);
                  return;
                }

                Map<String, String> settings;
                if (selectedType == 'webdav') {
                  settings = {
                    'url': urlController.text.trim(),
                    'username': usernameController.text.trim(),
                    'password': passwordController.text,
                    'use_proxy': useProxy.toString(),
                  };
                  final proxyUrl = proxyUrlController.text.trim();
                  if (proxyUrl.isNotEmpty) {
                    settings['proxy_url'] = proxyUrl;
                  }
                } else {
                  settings = {'path': urlController.text.trim()};
                }

                final success = await ref
                    .read(storagesProvider.notifier)
                    .addStorage(
                      name: name,
                      type: selectedType,
                      settings: settings,
                    );

                if (context.mounted) {
                  Navigator.pop(context);
                  IosUiUtils.showToast(
                    context: context,
                    message: success ? '添加成功' : '添加失败',
                    isError: !success,
                  );
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 存储源卡片
class _StorageCard extends StatelessWidget {
  final Storage storage;
  final bool isScanning;
  final ScanProgress? progress;
  final VoidCallback onScan;
  final VoidCallback onForceScrape;
  final VoidCallback onDelete;

  const _StorageCard({
    required this.storage,
    required this.isScanning,
    this.progress,
    required this.onScan,
    required this.onForceScrape,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  storage.type == 'webdav' ? CupertinoIcons.cloud : CupertinoIcons.folder,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storage.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        storage.typeDisplayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                PullDownButton(
                  itemBuilder: (context) => [
                    PullDownMenuItem(
                      title: '删除',
                      icon: CupertinoIcons.trash,
                      isDestructive: true,
                      onTap: onDelete,
                    ),
                  ],
                  buttonBuilder: (context, showMenu) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: showMenu,
                    child: const Icon(CupertinoIcons.ellipsis_circle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 扫描进度
            if (isScanning && progress != null) ...[
              LinearProgressIndicator(value: progress!.progress / 100),
              const SizedBox(height: 8),
              Text(
                '${progress!.statusText}: ${progress!.scannedFiles}/${progress!.totalFiles}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: isScanning ? null : onForceScrape,
                  icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                  label: const Text('强制刮削'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: isScanning ? null : onScan,
                  icon:
                      isScanning
                          ? const CupertinoActivityIndicator(radius: 8)
                          : const Icon(CupertinoIcons.refresh),
                  label: Text(isScanning ? '扫描中...' : '扫描'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
