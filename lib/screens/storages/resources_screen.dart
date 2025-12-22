import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 资源库页面（类似资源管理器入口）
///
/// 目标：
/// - 展示存储源列表
/// - 点击存储源进入“目录浏览”（像文件资源管理器一样逐级进入）
/// - 保留“扫描”能力（便于继续入库/刮削）
/// - 存储源新增/删除等管理能力放到“存储源管理”页面
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

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopTitleBar(
                title: const Text('资源库'),
                centerTitle: true,
                actions: [
                  IconButton(
                    tooltip: '存储源管理',
                    onPressed: () => context.push('/storage-manage'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              )
              : AppBar(
                title: const Text('资源库'),
                actions: [
                  IconButton(
                    tooltip: '存储源管理',
                    onPressed: () => context.push('/storage-manage'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
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
            return EmptyWidget(
              message: '暂无存储源\n请先添加存储源',
              icon: Icons.storage_outlined,
              action: FilledButton.icon(
                onPressed: () => context.push('/storage-manage'),
                icon: const Icon(Icons.add),
                label: const Text('去添加'),
              ),
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
                  onBrowse:
                      () => context.push(
                        '/storages/${storage.id}',
                        extra: storage,
                      ),
                  onScan: () => _startScan(storage.id),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _startScan(int storageId) async {
    final success = await ref
        .read(scanStateProvider.notifier)
        .startScan(storageId);
    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动扫描失败')));
    }
  }
}

/// 存储源卡片（资源库入口）
class _StorageCard extends StatelessWidget {
  final Storage storage;
  final bool isScanning;
  final ScanProgress? progress;
  final VoidCallback onBrowse;
  final VoidCallback onScan;

  const _StorageCard({
    required this.storage,
    required this.isScanning,
    this.progress,
    required this.onBrowse,
    required this.onScan,
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
                  storage.type == 'webdav' ? Icons.cloud : Icons.folder,
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

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('浏览'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isScanning ? null : onScan,
                  icon:
                      isScanning
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh),
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
