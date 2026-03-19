import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../../core/widgets/download_indicators.dart';

class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  final GlobalKey _refreshButtonKey = GlobalKey();
  final LayerLink _refreshButtonLink = LayerLink();
  OverlayEntry? _popoverEntry;

  @override
  void dispose() {
    _removePopover();
    super.dispose();
  }

  void _removePopover() {
    _popoverEntry?.remove();
    _popoverEntry = null;
  }

  void _showPopover() {
    _removePopover();
    _popoverEntry = OverlayEntry(
      builder: (context) {
        final state = ref.read(globalScanStateProvider);
        return _ScanPopoverOverlay(
          link: _refreshButtonLink,
          state: state,
          onClose: () {
            ref.read(globalScanStateProvider.notifier).dismiss();
            _removePopover();
          },
          onCancel: () {
            ref.read(globalScanStateProvider.notifier).cancelAllScans();
          },
        );
      },
    );
    Overlay.of(context).insert(_popoverEntry!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storagesProvider.notifier).loadStorages();
    });
  }

  Future<void> _startGlobalScan({bool forceScrape = false}) async {
    final result = await ref
        .read(globalScanStateProvider.notifier)
        .startScanAll(forceScrape: forceScrape);
    if (!mounted) return;
    DialogUtils.showToast(
      context: context,
      message: result.message,
      isError: !result.started,
    );
  }

  Future<void> _startGlobalScanFromMenu(
    BuildContext menuContext, {
    required bool forceScrape,
  }) async {
    await shadcn.closeOverlay(menuContext);
    if (!mounted) return;
    await _startGlobalScan(forceScrape: forceScrape);
  }

  void _showScanMenu(BuildContext context) {
    shadcn.showDropdown(
      context: context,
      builder:
          (dropdownContext) => shadcn.DropdownMenu(
            children: [
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.doc_text_search, size: 18),
                child: const Text('扫描新文件'),
                onPressed: (menuContext) async {
                  await _startGlobalScanFromMenu(
                    menuContext,
                    forceScrape: false,
                  );
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  size: 18,
                ),
                child: const Text('强制刮削全部'),
                onPressed: (menuContext) async {
                  await _startGlobalScanFromMenu(
                    menuContext,
                    forceScrape: true,
                  );
                },
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storagesAsync = ref.watch(storagesProvider);
    final globalScanState = ref.watch(globalScanStateProvider);
    final downloadState = ref.watch(downloadManagerProvider);
    final hasActiveDownloads = downloadState.downloadingTasks.isNotEmpty;
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);

    // 监听扫描状态变化，自动管理弹窗
    ref.listen<GlobalScanState>(globalScanStateProvider, (prev, next) {
      final shouldShow =
          !next.dismissed && (next.isScanning || next.foundFiles > 0);

      if (shouldShow && _popoverEntry == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _popoverEntry == null) _showPopover();
        });
      } else if (!shouldShow && _popoverEntry != null) {
        _removePopover();
      } else if (shouldShow && _popoverEntry != null) {
        _popoverEntry!.markNeedsBuild();
      }
    });

    return Scaffold(
      backgroundColor: context.appColors.groupedBackground,
      appBar:
          isDesktop
              ? DesktopTitleBar(
                title: const Text('资源库'),
                centerTitle: true,
                actions: [
                  IconButton(
                    tooltip: '下载管理',
                    onPressed: () => context.push('/download-manager'),
                    icon:
                        hasActiveDownloads
                            ? const AnimatedDownloadIndicator(size: 20)
                            : const Icon(shadcn.LucideIcons.circleArrowDown),
                  ),
                  CompositedTransformTarget(
                    link: _refreshButtonLink,
                    child:
                        globalScanState.isScanning
                            ? IconButton(
                              key: _refreshButtonKey,
                              tooltip: '扫描存储源',
                              onPressed:
                                  () =>
                                      ref
                                          .read(
                                            globalScanStateProvider.notifier,
                                          )
                                          .showPopover(),
                              icon: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : Builder(
                              builder:
                                  (menuContext) => IconButton(
                                    key: _refreshButtonKey,
                                    tooltip: '扫描存储源',
                                    onPressed: () => _showScanMenu(menuContext),
                                    icon: const Icon(
                                      shadcn.LucideIcons.refreshCw,
                                    ),
                                  ),
                            ),
                  ),
                  IconButton(
                    tooltip: '存储源管理',
                    onPressed: () => context.push('/storage-manage'),
                    icon: const Icon(shadcn.LucideIcons.database),
                  ),
                ],
              )
              : AppBar(
                title: const Text('资源库'),
                actions: [
                  IconButton(
                    tooltip: '下载管理',
                    onPressed: () => context.push('/download-manager'),
                    icon:
                        hasActiveDownloads
                            ? const AnimatedDownloadIndicator(size: 20)
                            : const Icon(shadcn.LucideIcons.circleArrowDown),
                  ),
                  CompositedTransformTarget(
                    link: _refreshButtonLink,
                    child:
                        globalScanState.isScanning
                            ? IconButton(
                              key: _refreshButtonKey,
                              tooltip: '扫描存储源',
                              onPressed:
                                  () =>
                                      ref
                                          .read(
                                            globalScanStateProvider.notifier,
                                          )
                                          .showPopover(),
                              icon: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : Builder(
                              builder:
                                  (menuContext) => IconButton(
                                    key: _refreshButtonKey,
                                    tooltip: '扫描存储源',
                                    onPressed: () => _showScanMenu(menuContext),
                                    icon: const Icon(
                                      shadcn.LucideIcons.refreshCw,
                                    ),
                                  ),
                            ),
                  ),
                  IconButton(
                    tooltip: '存储源管理',
                    onPressed: () => context.push('/storage-manage'),
                    icon: const Icon(shadcn.LucideIcons.database),
                  ),
                ],
              ),
      body: Stack(
        children: [
          storagesAsync.when(
            loading: () => const StoragesSkeletonLoader(),
            error:
                (error, stack) => AppErrorWidget(
                  message: error.toString(),
                  onRetry:
                      () => ref.read(storagesProvider.notifier).loadStorages(),
                ),
            data: (storages) {
              if (storages.isEmpty) {
                return EmptyWidget(
                  message: '暂无存储源\n请先添加存储源',
                  icon: CupertinoIcons.folder_badge_plus,
                  action: FilledButton.icon(
                    onPressed: () => context.push('/storage-manage'),
                    icon: const Icon(CupertinoIcons.add),
                    label: const Text('去添加'),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh:
                    () => ref.read(storagesProvider.notifier).loadStorages(),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    _buildSectionHeader('存储源', theme),
                    _buildStorageList(context, theme, storages),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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

  Widget _buildStorageList(
    BuildContext context,
    ThemeData theme,
    List<Storage> storages,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < storages.length; i++) ...[
            _StorageTile(
              storage: storages[i],
              onBrowse:
                  () => context.push(
                    '/storages/${storages[i].id}',
                    extra: storages[i],
                  ),
              onEdit: () => _editStorage(storages[i]),
              onDelete: () => _confirmDeleteStorage(storages[i]),
            ),
            if (i < storages.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _editStorage(Storage storage) {
    final settings = storage.settings ?? {};
    final nameController = TextEditingController(text: storage.name);
    final urlController = TextEditingController(
      text: settings['url'] ?? settings['path'] ?? '',
    );
    final usernameController = TextEditingController(
      text: settings['username'] ?? '',
    );
    final passwordController = TextEditingController(
      text: settings['password'] ?? '',
    );
    final proxyUrlController = TextEditingController(
      text: settings['proxy_url'] ?? '',
    );
    final publicBaseUrlController = TextEditingController(
      text:
          settings['public_base_url'] ??
          settings['base_url'] ??
          settings['public_url'] ??
          '',
    );
    String selectedType = storage.type;
    bool useProxy = settings['use_proxy'] == 'true';
    String streamMode =
        settings['stream_mode'] ??
        (selectedType == 'local' ? 'proxy' : 'redirect');
    bool obscurePassword = true;
    bool isTesting = false;

    showCupertinoDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => CupertinoAlertDialog(
                  title: const Text('编辑存储源'),
                  content: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoTextField(
                            controller: nameController,
                            placeholder: '名称',
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
                              obscureText: obscurePassword,
                              suffix: GestureDetector(
                                onTap:
                                    () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    obscurePassword
                                        ? CupertinoIcons.eye
                                        : CupertinoIcons.eye_slash,
                                    size: 20,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '使用代理访问',
                                  style: TextStyle(fontSize: 14),
                                ),
                                CupertinoSwitch(
                                  value: useProxy,
                                  onChanged: (value) {
                                    setState(() {
                                      useProxy = value;
                                      if (!useProxy) proxyUrlController.clear();
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
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '流媒体模式',
                                  style: TextStyle(fontSize: 14),
                                ),
                                CupertinoSlidingSegmentedControl<String>(
                                  groupValue: streamMode,
                                  children: const {
                                    'proxy': Text('代理'),
                                    'redirect': Text('直连'),
                                  },
                                  onValueChanged: (value) {
                                    setState(() => streamMode = value!);
                                  },
                                ),
                              ],
                            ),
                          ] else ...[
                            CupertinoTextField(
                              controller: urlController,
                              placeholder: '路径',
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '流媒体模式',
                                  style: TextStyle(fontSize: 14),
                                ),
                                CupertinoSlidingSegmentedControl<String>(
                                  groupValue: streamMode,
                                  children: const {
                                    'proxy': Text('代理'),
                                    'redirect': Text('直连'),
                                  },
                                  onValueChanged: (value) {
                                    setState(() {
                                      streamMode = value!;
                                      if (streamMode != 'redirect') {
                                        publicBaseUrlController.clear();
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (streamMode == 'redirect') ...[
                              const SizedBox(height: 8),
                              CupertinoTextField(
                                controller: publicBaseUrlController,
                                placeholder:
                                    '直连基地址（如：http://nas.local:8081/media）',
                                keyboardType: TextInputType.url,
                              ),
                            ],
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
                      onPressed:
                          isTesting
                              ? null
                              : () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  DialogUtils.showToast(
                                    context: context,
                                    message: '请输入名称',
                                    isError: true,
                                  );
                                  return;
                                }

                                Map<String, String> newSettings;
                                if (selectedType == 'webdav') {
                                  newSettings = {
                                    'url': urlController.text.trim(),
                                    'username': usernameController.text.trim(),
                                    'password': passwordController.text,
                                    'use_proxy': useProxy.toString(),
                                    'stream_mode': streamMode,
                                  };
                                  final proxyUrl =
                                      proxyUrlController.text.trim();
                                  if (proxyUrl.isNotEmpty) {
                                    newSettings['proxy_url'] = proxyUrl;
                                  }
                                } else {
                                  if (streamMode == 'redirect' &&
                                      publicBaseUrlController.text
                                          .trim()
                                          .isEmpty) {
                                    DialogUtils.showToast(
                                      context: context,
                                      message: '直连模式需要填写直连基地址',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  newSettings = {
                                    'path': urlController.text.trim(),
                                    'stream_mode': streamMode,
                                  };
                                  final publicBaseUrl =
                                      publicBaseUrlController.text.trim();
                                  if (publicBaseUrl.isNotEmpty) {
                                    newSettings['public_base_url'] =
                                        publicBaseUrl;
                                  }
                                }

                                setState(() => isTesting = true);

                                final success = await ref
                                    .read(storagesProvider.notifier)
                                    .updateStorage(
                                      id: storage.id,
                                      name: name,
                                      type: selectedType,
                                      settings: newSettings,
                                    );

                                if (!success) {
                                  setState(() => isTesting = false);
                                  if (context.mounted) {
                                    DialogUtils.showToast(
                                      context: context,
                                      message: '保存失败',
                                      isError: true,
                                    );
                                  }
                                  return;
                                }

                                await browseStorage(ref, storage.id, '/');
                                setState(() => isTesting = false);

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  final browseState = ref.read(
                                    browseProvider(storage.id),
                                  );
                                  if (browseState.error != null) {
                                    DialogUtils.showToast(
                                      context: context,
                                      message: '已保存，但连接测试失败',
                                      isError: true,
                                    );
                                  } else {
                                    DialogUtils.showToast(
                                      context: context,
                                      message: '保存成功',
                                    );
                                  }
                                }
                              },
                      child:
                          isTesting
                              ? const CupertinoActivityIndicator()
                              : const Text('保存'),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _confirmDeleteStorage(Storage storage) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '删除存储源',
      content: '确定要删除「${storage.name}」吗？\n\n删除后相关的媒体信息也会被移除。',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(storagesProvider.notifier)
          .deleteStorage(storage.id);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '已删除' : '删除失败',
          isError: !success,
        );
      }
    }
  }
}

class _StorageTile extends StatelessWidget {
  final Storage storage;
  final VoidCallback onBrowse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StorageTile({
    required this.storage,
    required this.onBrowse,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = storage.type == 'webdav' ? Colors.blue : Colors.orange;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onBrowse,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  storage.type == 'webdav'
                      ? CupertinoIcons.globe
                      : CupertinoIcons.folder,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storage.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      storage.typeDisplayName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // showDropdown 会使用传入的 context 作为“锚点”定位菜单。
              // 如果直接用整行 Tile 的 context，菜单会更靠近 Tile 的中间。
              // 这里用 Builder 获取“...”按钮自身的 context，确保菜单在按钮正下方弹出。
              Builder(
                builder: (menuContext) {
                  return GestureDetector(
                    onTap: () => _showActionMenu(menuContext),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        size: 20,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionMenu(BuildContext context) {
    // 原先使用 CupertinoActionSheet（更偏“底部弹出”），这里按需求改为 shadcn_flutter 的 DropdownMenu。
    // DropdownMenu 的交互更贴近“点击…弹出菜单栏”，也便于后续统一样式。
    shadcn.showDropdown(
      context: context,
      builder: (dropdownContext) {
        final theme = Theme.of(dropdownContext);
        final destructiveColor = theme.colorScheme.error;

        return shadcn.DropdownMenu(
          children: [
            shadcn.MenuButton(
              leading: const Icon(CupertinoIcons.pencil, size: 18),
              child: const Text('编辑存储源'),
              onPressed: (menuContext) {
                shadcn.closeOverlay(menuContext);
                onEdit();
              },
            ),
            shadcn.MenuButton(
              leading: Icon(
                CupertinoIcons.trash,
                size: 18,
                color: destructiveColor,
              ),
              child: Text('删除存储源', style: TextStyle(color: destructiveColor)),
              onPressed: (menuContext) {
                shadcn.closeOverlay(menuContext);
                onDelete();
              },
            ),
          ],
        );
      },
    );
  }
}

class _ScanPopoverOverlay extends StatelessWidget {
  final LayerLink link;
  final GlobalScanState state;
  final VoidCallback onClose;
  final VoidCallback onCancel;

  const _ScanPopoverOverlay({
    required this.link,
    required this.state,
    required this.onClose,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const desiredWidthMobile = 280.0;
    const horizontalMargin = 16.0;
    final maxWidth = math.max(0.0, screenWidth - horizontalMargin * 2);
    final popoverWidth = math.min(desiredWidthMobile, maxWidth);

    // 三角形相对于弹窗右边缘的偏移（让三角指向按钮中心）
    const triangleRightOffset = 40.0;

    return Positioned(
      top: 0,
      left: 0,
      child: CompositedTransformFollower(
        link: link,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topRight,
        offset: const Offset(triangleRightOffset + 8, 8), // 向左偏移，让右边缘留出空间
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: popoverWidth,
            constraints: BoxConstraints(
              maxWidth: screenWidth - horizontalMargin * 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 小三角（右侧偏移）
                Padding(
                  padding: const EdgeInsets.only(right: triangleRightOffset),
                  child: CustomPaint(
                    size: const Size(16, 8),
                    painter: _TrianglePainter(),
                  ),
                ),
                // 气泡主体
                Container(
                  width: popoverWidth,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            state.isScanning ? '正在扫描' : '扫描完成',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          GestureDetector(
                            onTap: onClose,
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.isDiscovering
                            ? (state.discoveredFiles > 0
                                ? '正在扫描... 已发现 ${state.discoveredFiles} 个文件'
                                : '正在扫描目录...')
                            : '已找到 ${state.foundFiles}，待更新 ${state.pendingFiles}，已更新 ${state.updatedFiles}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                      if (state.isScanning) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: onCancel,
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('取消扫描'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.fill;
    final path =
        Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
