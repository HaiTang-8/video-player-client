import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              title: const Text('资源库'),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: '存储源管理',
                  onPressed: () => context.push('/storage-manage'),
                  icon: const Icon(CupertinoIcons.gear),
                ),
              ],
            )
          : AppBar(
              title: const Text('资源库'),
              actions: [
                IconButton(
                  tooltip: '存储源管理',
                  onPressed: () => context.push('/storage-manage'),
                  icon: const Icon(CupertinoIcons.gear),
                ),
              ],
            ),
      body: storagesAsync.when(
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
                _buildStorageList(context, theme, storages, scanState),
              ],
            ),
          );
        },
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
    ScanState scanState,
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
              isScanning: scanState.scanning.contains(storages[i].id),
              progress: scanState.progresses[storages[i].id],
              onBrowse: () => context.push(
                '/storages/${storages[i].id}',
                extra: storages[i],
              ),
              onScan: () => _startScan(storages[i].id),
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

  Future<void> _startScan(int storageId) async {
    final success = await ref.read(scanStateProvider.notifier).startScan(storageId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('启动扫描失败')),
      );
    }
  }
}

class _StorageTile extends StatelessWidget {
  final Storage storage;
  final bool isScanning;
  final ScanProgress? progress;
  final VoidCallback onBrowse;
  final VoidCallback onScan;

  const _StorageTile({
    required this.storage,
    required this.isScanning,
    this.progress,
    required this.onBrowse,
    required this.onScan,
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
          child: Column(
            children: [
              Row(
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
                          ? CupertinoIcons.cloud
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
                  _buildActionButton(context, theme),
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
              if (isScanning && progress != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.progress / 100,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${progress!.statusText}: ${progress!.scannedFiles}/${progress!.totalFiles}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, ThemeData theme) {
    if (isScanning) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return GestureDetector(
      onTap: onScan,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '扫描',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
