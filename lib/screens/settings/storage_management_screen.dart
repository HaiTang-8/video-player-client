import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/storage_management_service.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  State<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen> {
  final _service = StorageManagementService.instance;
  List<StorageCategory> _categories = [];
  bool _isLoading = true;
  String? _clearingId;

  @override
  void initState() {
    super.initState();
    _loadStorageUsage();
  }

  Future<void> _loadStorageUsage() async {
    setState(() => _isLoading = true);
    final categories = await _service.getStorageUsage();
    if (mounted) {
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCategory(StorageCategory category) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('清除${category.name}'),
        content: Text(
          category.id == 'downloads'
              ? '确定要删除所有已下载的视频文件吗？此操作不可恢复。'
              : '确定要清除${category.name}吗？',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _clearingId = category.id);
      await _service.clearCategory(category.id);
      await _loadStorageUsage();
      if (mounted) {
        setState(() => _clearingId = null);
      }
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清除所有缓存'),
        content: const Text('将清除图片缓存、日志文件和临时文件。下载的视频文件不会被删除。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _clearingId = 'all');
      await _service.clearAll();
      await _loadStorageUsage();
      if (mounted) {
        setState(() => _clearingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = WindowControls.isDesktop;

    final totalSize =
        _categories.fold<int>(0, (sum, cat) => sum + cat.size);

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('存储空间'),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: const Text('存储空间'),
              onBack: () => context.pop(),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStorageUsage,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 总存储使用
                  _buildTotalUsageCard(theme, isDark, totalSize),
                  const SizedBox(height: 24),

                  // 分类列表
                  _buildSectionHeader('存储分类', theme),
                  const SizedBox(height: 8),
                  _buildCategoriesCard(theme, isDark),
                  const SizedBox(height: 24),

                  // 清除所有缓存按钮
                  _buildClearAllButton(theme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildTotalUsageCard(ThemeData theme, bool isDark, int totalSize) {
    final isDesktop = WindowControls.isDesktop;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2C2C2E), const Color(0xFF1C1C1E)]
              : [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isDesktop ? CupertinoIcons.desktopcomputer : CupertinoIcons.device_phone_portrait,
            size: 48,
            color: isDark ? Colors.white70 : Colors.blue.shade700,
          ),
          const SizedBox(height: 12),
          Text(
            _service.formatSize(totalSize),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.blue.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '已使用存储空间',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white60 : Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCategoriesCard(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: _categories.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value;
          final isLast = index == _categories.length - 1;

          return Column(
            children: [
              _buildCategoryTile(theme, isDark, category),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: 1,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryTile(
    ThemeData theme,
    bool isDark,
    StorageCategory category,
  ) {
    final iconData = _getCategoryIcon(category.id);
    final iconColor = _getCategoryColor(category.id);
    final isClearing = _clearingId == category.id || _clearingId == 'all';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: category.size > 0 && category.canClear && !isClearing
            ? () => _clearCategory(category)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconData, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isClearing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  _service.formatSize(category.size),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: category.size > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (category.size > 0 && category.canClear && !isClearing) ...[
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClearAllButton(ThemeData theme) {
    final cacheSize = _categories
        .where((c) => c.id != 'downloads')
        .fold<int>(0, (sum, c) => sum + c.size);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: cacheSize > 0 && _clearingId == null
            ? _clearAllCache
            : null,
        icon: _clearingId == 'all'
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(CupertinoIcons.trash),
        label: Text('清除所有缓存 (${_service.formatSize(cacheSize)})'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String id) {
    switch (id) {
      case 'downloads':
        return CupertinoIcons.arrow_down_circle_fill;
      case 'image_cache':
        return CupertinoIcons.photo_fill;
      case 'logs':
        return CupertinoIcons.doc_text_fill;
      default:
        return CupertinoIcons.circle_fill;
    }
  }

  Color _getCategoryColor(String id) {
    switch (id) {
      case 'downloads':
        return Colors.green;
      case 'image_cache':
        return Colors.purple;
      case 'logs':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}
