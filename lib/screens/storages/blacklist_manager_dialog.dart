import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/dialog_utils.dart';
import '../../providers/providers.dart';

class BlacklistManagerDialog extends ConsumerStatefulWidget {
  final int storageId;

  const BlacklistManagerDialog({super.key, required this.storageId});

  @override
  ConsumerState<BlacklistManagerDialog> createState() =>
      _BlacklistManagerDialogState();
}

class _BlacklistManagerDialogState
    extends ConsumerState<BlacklistManagerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 1;
  static const _pageSize = 10;

  List<String> _blacklist = [];
  int _total = 0;
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBlacklist();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadBlacklist() async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;

    setState(() => _isLoading = true);

    final response = await service.getBlacklist(
      widget.storageId,
      page: _currentPage,
      pageSize: _pageSize,
      keyword: _searchQuery.isNotEmpty ? _searchQuery : null,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.isSuccess && response.data != null) {
          _blacklist = response.data!;
          _total = response.total ?? 0;
        }
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = value;
        _currentPage = 1;
      });
      _loadBlacklist();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final totalPages = (_total / _pageSize).ceil();

    final destructiveStyle = shadcn.ButtonVariance.destructive.withBackgroundColor(
      color: theme.colorScheme.destructive,
      hoverColor: theme.colorScheme.destructive,
      focusColor: theme.colorScheme.destructive,
    );

    return shadcn.AlertDialog(
      barrierColor: Colors.transparent,
      surfaceOpacity: 1,
      title: Row(
        children: [
          Icon(
            shadcn.LucideIcons.ban,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text('扫描黑名单'),
        ],
      ),
      content: SizedBox(
        height: 360,
        child: Column(
          children: [
            // 搜索框
            Row(
              children: [
                Expanded(
                  child: shadcn.TextField(
                    controller: _searchController,
                    placeholder: const Text('搜索路径...'),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  shadcn.GhostButton(
                    size: shadcn.ButtonSize.small,
                    density: shadcn.ButtonDensity.icon,
                    onPressed: () {
                      _searchController.clear();
                      _debounce?.cancel();
                      setState(() {
                        _searchQuery = '';
                        _currentPage = 1;
                      });
                      _loadBlacklist();
                    },
                    child: Icon(
                      shadcn.LucideIcons.x,
                      size: 16,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // 列表区域
            Expanded(
              child: _isLoading
                  ? const Center(child: shadcn.CircularProgressIndicator())
                  : _blacklist.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                shadcn.LucideIcons.folderMinus,
                                size: 48,
                                color: theme.colorScheme.mutedForeground
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? '未找到匹配的路径'
                                    : '暂无黑名单目录',
                                style: theme.typography.base.copyWith(
                                  color: theme.colorScheme.mutedForeground,
                                ),
                              ),
                              if (_searchQuery.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '长按目录可添加到黑名单',
                                  style: theme.typography.small.copyWith(
                                    color: theme.colorScheme.mutedForeground
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final minWidth = constraints.maxWidth.isFinite
                                ? constraints.maxWidth
                                : 0.0;
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: minWidth),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: _blacklist.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final path = entry.value;
                                    return Column(
                                      children: [
                                        if (index > 0)
                                          Divider(
                                            height: 1,
                                            color: theme.colorScheme.border
                                                .withValues(alpha: 0.3),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 4,
                                          ),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    shadcn.LucideIcons.folder,
                                                    size: 20,
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    path,
                                                    style: theme.typography.small,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                shadcn.GhostButton(
                                                  size: shadcn.ButtonSize.small,
                                                  density:
                                                      shadcn.ButtonDensity.icon,
                                                  onPressed: () =>
                                                      _removeFromBlacklist(path),
                                                  child: Icon(
                                                    shadcn.LucideIcons.x,
                                                    size: 16,
                                                    color: theme
                                                        .colorScheme.mutedForeground,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // 分页控件
            if (totalPages > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  shadcn.GhostButton(
                    size: shadcn.ButtonSize.small,
                    density: shadcn.ButtonDensity.icon,
                    enabled: _currentPage > 1,
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() => _currentPage--);
                            _loadBlacklist();
                          }
                        : null,
                    child: Icon(
                      shadcn.LucideIcons.chevronLeft,
                      size: 16,
                      color: _currentPage > 1
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_currentPage / $totalPages',
                    style: theme.typography.small,
                  ),
                  const SizedBox(width: 8),
                  shadcn.GhostButton(
                    size: shadcn.ButtonSize.small,
                    density: shadcn.ButtonDensity.icon,
                    enabled: _currentPage < totalPages,
                    onPressed: _currentPage < totalPages
                        ? () {
                            setState(() => _currentPage++);
                            _loadBlacklist();
                          }
                        : null,
                    child: Icon(
                      shadcn.LucideIcons.chevronRight,
                      size: 16,
                      color: _currentPage < totalPages
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_total > 0)
          shadcn.Button.destructive(
            style: destructiveStyle,
            disableFocusOutline: true,
            onPressed: _clearAll,
            child: const Text('清空全部'),
          ),
        shadcn.OutlineButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _removeFromBlacklist(String path) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '确认移除',
      content: '确定要从黑名单移除此目录吗？\n$path',
      isDestructive: true,
      confirmText: '移除',
    );

    if (confirmed != true || !mounted) return;

    final success = await removeFromBlacklist(ref, widget.storageId, path);
    if (mounted && success) {
      DialogUtils.showToast(context: context, message: '已从黑名单移除');
      _loadBlacklist();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '确认清空',
      content: '确定要清空所有黑名单目录吗？',
      isDestructive: true,
      confirmText: '清空',
    );

    if (confirmed == true && mounted) {
      final success = await clearBlacklist(ref, widget.storageId);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '已清空黑名单' : '清空失败',
          isError: !success,
        );
        if (success) {
          setState(() {
            _blacklist = [];
            _total = 0;
            _currentPage = 1;
          });
        }
      }
    }
  }
}
