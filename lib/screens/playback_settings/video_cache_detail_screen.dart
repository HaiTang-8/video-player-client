import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/log_service.dart';
import '../../data/services/storage_management_service.dart';
import '../../playback/cache/playback_cache_catalog.dart';
import '../../playback/playback_providers.dart';

class VideoCacheDetailScreen extends ConsumerStatefulWidget {
  const VideoCacheDetailScreen({super.key});

  @override
  ConsumerState<VideoCacheDetailScreen> createState() =>
      _VideoCacheDetailScreenState();
}

class _VideoCacheDetailScreenState
    extends ConsumerState<VideoCacheDetailScreen> {
  final _storageService = StorageManagementService.instance;
  List<CachedVideo> _entries = [];
  bool _isLoading = true;
  Object? _error;
  String? _deletingId;

  PlaybackCacheCatalog get _catalog => ref.read(playbackCacheCatalogProvider);

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await _catalog.entries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      LogService.instance.warn('PlaybackCache', 'Failed to list entries: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _isLoading = true);
    await _loadEntries();
  }

  Future<void> _deleteEntry(CachedVideo entry) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '删除缓存',
      content: '确定要删除「${entry.name}」的缓存吗？',
      confirmText: '删除',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = entry.id);
    try {
      await _catalog.remove(entry.id);
    } finally {
      await _loadEntries();
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '清除全部缓存',
      content: '将删除所有播放缓存，已下载的视频不会被删除。',
      confirmText: '清除',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _catalog.clearCache();
    } finally {
      await _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = WindowControls.isDesktop;
    final totalSize = _entries.fold<int>(0, (sum, e) => sum + e.cachedBytes);

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopAppBar(
                title: const Text('播放缓存'),
                onBack: () => context.pop(),
              )
              : MobileAppBar(
                title: const Text('播放缓存'),
                onBack: () => context.pop(),
              ),
      body:
          _isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : _error != null
              ? AppErrorWidget(message: '无法读取播放缓存，请稍后重试', onRetry: _retry)
              : RefreshIndicator(
                onRefresh: _loadEntries,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildTotalUsageCard(theme, isDark, totalSize),
                    const SizedBox(height: 24),
                    if (_entries.isEmpty)
                      _buildEmptyState(theme)
                    else ...[
                      _buildSectionHeader('缓存列表', theme),
                      const SizedBox(height: 8),
                      _buildEntriesCard(theme, isDark),
                      const SizedBox(height: 24),
                      _buildClearAllButton(totalSize),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
    );
  }

  Widget _buildTotalUsageCard(ThemeData theme, bool isDark, int totalSize) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isDark
                  ? [const Color(0xFF2C2C2E), const Color(0xFF1C1C1E)]
                  : [Colors.indigo.shade50, Colors.indigo.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.tray_full,
            size: 48,
            color: isDark ? Colors.white70 : Colors.indigo.shade700,
          ),
          const SizedBox(height: 12),
          Text(
            _storageService.formatSize(totalSize),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_entries.length} 个视频',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white60 : Colors.indigo.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.tray,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无播放缓存',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '播放视频时会自动缓存，再次打开时可以更快开始播放',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEntriesCard(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (index, entry) in _entries.indexed) ...[
            _buildEntryTile(theme, isDark, entry),
            if (index < _entries.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 64),
                child: Divider(
                  height: 1,
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryTile(ThemeData theme, bool isDark, CachedVideo entry) {
    final isDeleting = _deletingId == entry.id;
    final color = entry.complete ? Colors.green : Colors.orange;
    final size =
        entry.complete
            ? _storageService.formatSize(entry.cachedBytes)
            : '${_storageService.formatSize(entry.cachedBytes)} / '
                '${_storageService.formatSize(entry.sizeBytes)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            isDeleting || _deletingId != null
                ? null
                : () => _deleteEntry(entry),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  entry.complete
                      ? CupertinoIcons.checkmark_circle
                      : CupertinoIcons.play_rectangle,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$size · ${entry.complete ? '完整' : '部分'} · '
                      '${_formatRelativeTime(entry.lastAccess)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDeleting)
                const CupertinoActivityIndicator()
              else
                Icon(
                  CupertinoIcons.delete,
                  size: 18,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${time.month}月${time.day}日';
  }

  Widget _buildClearAllButton(int totalSize) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed:
            _entries.isNotEmpty && _deletingId == null ? _clearAll : null,
        icon: const Icon(CupertinoIcons.trash),
        label: Text('清除全部缓存 (${_storageService.formatSize(totalSize)})'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}
