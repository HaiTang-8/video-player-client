import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  final GlobalKey _refreshButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storagesProvider.notifier).loadStorages();
    });
  }

  void _startGlobalScan({bool forceScrape = false}) {
    ref.read(globalScanStateProvider.notifier).startScanAll(forceScrape: forceScrape);
  }

  List<PullDownMenuEntry> _buildScanMenuItems() {
    return [
      PullDownMenuItem(
        title: '扫描新文件',
        icon: CupertinoIcons.doc_text_search,
        onTap: () => _startGlobalScan(forceScrape: false),
      ),
      PullDownMenuItem(
        title: '强制刮削全部',
        icon: CupertinoIcons.arrow_2_circlepath,
        onTap: () => _startGlobalScan(forceScrape: true),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final storagesAsync = ref.watch(storagesProvider);
    final globalScanState = ref.watch(globalScanStateProvider);
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFF2F2F7),
      appBar: isDesktop
          ? DesktopTitleBar(
              title: const Text('资源库'),
              centerTitle: true,
              actions: [
                if (globalScanState.isScanning)
                  IconButton(
                    key: _refreshButtonKey,
                    tooltip: '扫描存储源',
                    onPressed: () => ref.read(globalScanStateProvider.notifier).showPopover(),
                    icon: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PullDownButton(
                    key: _refreshButtonKey,
                    itemBuilder: (context) => _buildScanMenuItems(),
                    buttonBuilder: (context, showMenu) => IconButton(
                      tooltip: '扫描存储源',
                      onPressed: showMenu,
                      icon: const Icon(CupertinoIcons.refresh),
                    ),
                  ),
                IconButton(
                  tooltip: '添加存储源',
                  onPressed: () => context.push('/storage-manage'),
                  icon: const Icon(CupertinoIcons.add),
                ),
              ],
            )
          : AppBar(
              title: const Text('资源库'),
              actions: [
                if (globalScanState.isScanning)
                  IconButton(
                    key: _refreshButtonKey,
                    tooltip: '扫描存储源',
                    onPressed: () => ref.read(globalScanStateProvider.notifier).showPopover(),
                    icon: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PullDownButton(
                    key: _refreshButtonKey,
                    itemBuilder: (context) => _buildScanMenuItems(),
                    buttonBuilder: (context, showMenu) => IconButton(
                      tooltip: '扫描存储源',
                      onPressed: showMenu,
                      icon: const Icon(CupertinoIcons.refresh),
                    ),
                  ),
                IconButton(
                  tooltip: '添加存储源',
                  onPressed: () => context.push('/storage-manage'),
                  icon: const Icon(CupertinoIcons.add),
                ),
              ],
            ),
      body: Stack(
        children: [
          storagesAsync.when(
            loading: () => const LoadingWidget(message: '加载中...'),
            error: (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry: () => ref.read(storagesProvider.notifier).loadStorages(),
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
                onRefresh: () => ref.read(storagesProvider.notifier).loadStorages(),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _buildSectionHeader('存储源', theme),
                    _buildStorageList(context, theme, storages),
                  ],
                ),
              );
            },
          ),
          if (!globalScanState.dismissed && (globalScanState.isScanning || globalScanState.foundFiles > 0))
            _ScanPopover(
              buttonKey: _refreshButtonKey,
              state: globalScanState,
              onClose: () => ref.read(globalScanStateProvider.notifier).dismiss(),
              onCancel: () => ref.read(globalScanStateProvider.notifier).cancelAllScans(),
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
              onBrowse: () => context.push(
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
    context.push('/storage-manage');
  }

  Future<void> _confirmDeleteStorage(Storage storage) async {
    final confirmed = await IosUiUtils.showConfirmDialog(
      context: context,
      title: '删除存储源',
      content: '确定要删除「${storage.name}」吗？\n\n删除后相关的媒体信息也会被移除。',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(storagesProvider.notifier).deleteStorage(storage.id);
      if (mounted) {
        IosUiUtils.showToast(
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
              GestureDetector(
                onTap: () => _showActionMenu(context, isDark),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionMenu(BuildContext context, bool isDark) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onEdit();
            },
            child: const Text('编辑存储源'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('删除存储源'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _ScanPopover extends StatefulWidget {
  final GlobalKey buttonKey;
  final GlobalScanState state;
  final VoidCallback onClose;
  final VoidCallback onCancel;

  const _ScanPopover({
    required this.buttonKey,
    required this.state,
    required this.onClose,
    required this.onCancel,
  });

  @override
  State<_ScanPopover> createState() => _ScanPopoverState();
}

class _ScanPopoverState extends State<_ScanPopover> {
  double? _buttonCenterX;
  double? _buttonBottom;

  @override
  void initState() {
    super.initState();
    _schedulePositionUpdate();
  }

  @override
  void didUpdateWidget(covariant _ScanPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePositionUpdate();
  }

  void _schedulePositionUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updatePosition();
    });
  }

  void _updatePosition() {
    final renderBox = widget.buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final pos = renderBox.localToGlobal(Offset.zero);
      if (mounted) {
        setState(() {
          _buttonCenterX = pos.dx + renderBox.size.width / 2;
          _buttonBottom = pos.dy + renderBox.size.height;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_buttonCenterX == null || _buttonBottom == null) {
      return const SizedBox.shrink();
    }

    const popoverWidth = 220.0;
    final screenWidth = MediaQuery.of(context).size.width;
    // body 的坐标系从 AppBar 下方开始，需要减去 AppBar 高度
    final appBarHeight = WindowControls.isDesktop ? 52.0 : kToolbarHeight;

    // 计算气泡左边位置，确保不超出屏幕
    double popoverLeft = _buttonCenterX! - popoverWidth / 2;
    popoverLeft = popoverLeft.clamp(16.0, screenWidth - popoverWidth - 16);

    // 计算小三角相对于气泡的偏移（让三角对准按钮中心）
    final triangleOffset = _buttonCenterX! - popoverLeft - 8; // 8 是三角宽度的一半

    return Positioned(
      left: popoverLeft,
      top: _buttonBottom! - appBarHeight + 8,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 小三角（通过 Padding 偏移到按钮正下方）
            Padding(
              padding: EdgeInsets.only(left: triangleOffset.clamp(8.0, popoverWidth - 24)),
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
                        widget.state.isScanning ? '正在扫描' : '扫描完成',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.state.foundFiles == 0 && widget.state.isScanning
                        ? '正在扫描目录...'
                        : '已找到 ${widget.state.foundFiles}，待更新 ${widget.state.pendingFiles}，已更新 ${widget.state.updatedFiles}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                  if (widget.state.isScanning) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: widget.onCancel,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
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
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
