import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/log_entry.dart';
import '../../data/services/log_service.dart';
import '../../providers/log_viewer_provider.dart';

class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  final _searchController = TextEditingController();
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(logViewerProvider.notifier).loadLogs());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final isDark = theme.colorScheme.brightness == Brightness.dark;
    final isDesktop = WindowControls.isDesktop;
    final state = ref.watch(logViewerProvider);

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('应用日志'),
              onBack: () => context.pop(),
              actions: [
                shadcn.GhostButton(
                  size: shadcn.ButtonSize.small,
                  density: shadcn.ButtonDensity.icon,
                  onPressed: () => ref.read(logViewerProvider.notifier).loadLogs(),
                  child: const Icon(shadcn.LucideIcons.refreshCw, size: 16),
                ),
                const SizedBox(width: 4),
                shadcn.GhostButton(
                  size: shadcn.ButtonSize.small,
                  density: shadcn.ButtonDensity.icon,
                  onPressed: () => _copyLogs(),
                  child: const Icon(shadcn.LucideIcons.copy, size: 16),
                ),
              ],
            )
          : MobileAppBar(
              title: const Text('应用日志'),
              onBack: () => context.pop(),
              actions: [
                IconButton(
                  icon: Icon(_showFilters ? CupertinoIcons.slider_horizontal_3 : CupertinoIcons.slider_horizontal_below_rectangle),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.doc_on_clipboard),
                  onPressed: () => _copyLogs(),
                ),
              ],
            ),
      body: isDesktop
          ? _buildDesktopLayout(theme, isDark, state)
          : _buildMobileLayout(theme, isDark, state),
    );
  }

  Widget _buildDesktopLayout(shadcn.ThemeData theme, bool isDark, LogViewerState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧筛选面板
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: theme.colorScheme.card,
            border: Border(
              right: BorderSide(color: theme.colorScheme.border),
            ),
          ),
          child: _buildDesktopFilterPanel(theme, isDark, state),
        ),
        // 右侧日志列表
        Expanded(
          child: Column(
            children: [
              _buildStatsBar(theme, state),
              Expanded(child: _buildLogList(theme, state)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(shadcn.ThemeData theme, bool isDark, LogViewerState state) {
    return Column(
      children: [
        if (_showFilters) _buildMobileFilterBar(theme, isDark, state),
        _buildStatsBar(theme, state),
        Expanded(child: _buildLogList(theme, state)),
      ],
    );
  }

  Widget _buildStatsBar(shadcn.ThemeData theme, LogViewerState state) {
    final infoCount = state.allLogs.where((e) => e.level == 'INFO').length;
    final warnCount = state.allLogs.where((e) => e.level == 'WARN').length;
    final errorCount = state.allLogs.where((e) => e.level == 'ERROR').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            '共 ${state.filteredLogs.length} 条',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.foreground,
            ),
          ),
          if (state.filteredLogs.length != state.allLogs.length)
            Text(
              ' / ${state.allLogs.length}',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          const Spacer(),
          _buildStatBadge('INFO', infoCount, Colors.grey, theme),
          const SizedBox(width: 8),
          _buildStatBadge('WARN', warnCount, Colors.orange, theme),
          const SizedBox(width: 8),
          _buildStatBadge('ERR', errorCount, Colors.red, theme),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, int count, Color color, shadcn.ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(shadcn.ThemeData theme, LogViewerState state) {
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '加载日志...',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    if (state.filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shadcn.LucideIcons.fileText,
              size: 48,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 16),
            Text(
              state.allLogs.isEmpty ? '暂无日志' : '无匹配结果',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            if (state.allLogs.isNotEmpty) ...[
              const SizedBox(height: 8),
              shadcn.GhostButton(
                size: shadcn.ButtonSize.small,
                onPressed: () {
                  ref.read(logViewerProvider.notifier).clearFilter();
                  _searchController.clear();
                },
                child: const Text('清除筛选'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(logViewerProvider.notifier).loadLogs(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: state.filteredLogs.length,
        itemBuilder: (context, index) {
          return _LogEntryCard(
            entry: state.filteredLogs[index],
            theme: theme,
          );
        },
      ),
    );
  }

  Widget _buildDesktopFilterPanel(shadcn.ThemeData theme, bool isDark, LogViewerState state) {
    final notifier = ref.read(logViewerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索框
          Row(
            children: [
              Icon(
                shadcn.LucideIcons.search,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: shadcn.TextField(
                  controller: _searchController,
                  placeholder: const Text('搜索日志...'),
                  onChanged: (value) => notifier.setKeyword(value),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                shadcn.GhostButton(
                  size: shadcn.ButtonSize.small,
                  density: shadcn.ButtonDensity.icon,
                  onPressed: () {
                    _searchController.clear();
                    notifier.setKeyword('');
                  },
                  child: Icon(
                    shadcn.LucideIcons.x,
                    size: 14,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // 日志级别
          _buildSectionHeader('日志级别', theme),
          const SizedBox(height: 8),
          ..._buildLevelCheckboxes(state, notifier, theme),
          const SizedBox(height: 20),

          // 标签筛选
          _buildSectionHeader('标签', theme),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: shadcn.Select<String?>(
              value: state.filter.tag,
              placeholder: const Text('全部标签'),
              itemBuilder: (context, item) => Text(item ?? '全部'),
              onChanged: (value) => notifier.setTag(value),
              popup: shadcn.SelectPopup(
                items: shadcn.SelectItemList(
                  children: [
                    shadcn.SelectItemButton(
                      value: null,
                      child: const Text('全部'),
                    ),
                    ...state.allTags.map((tag) => shadcn.SelectItemButton(
                          value: tag,
                          child: Text(tag),
                        )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 时间范围
          _buildSectionHeader('时间范围', theme),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: shadcn.DateRangePicker(
              value: state.filter.startDate != null && state.filter.endDate != null
                  ? shadcn.DateTimeRange(state.filter.startDate!, state.filter.endDate!)
                  : null,
              placeholder: const Text('选择日期范围'),
              mode: shadcn.PromptMode.dialog,
              dialogTitle: const Text('选择时间范围'),
              onChanged: (range) {
                if (range != null) {
                  notifier.setDateRange(range.start, range.end);
                } else {
                  notifier.setDateRange(null, null);
                }
              },
              stateBuilder: (date) => date.isAfter(DateTime.now())
                  ? shadcn.DateState.disabled
                  : shadcn.DateState.enabled,
            ),
          ),
          if (state.filter.startDate != null) ...[
            const SizedBox(height: 8),
            shadcn.GhostButton(
              size: shadcn.ButtonSize.small,
              onPressed: () => notifier.setDateRange(null, null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(shadcn.LucideIcons.x, size: 12, color: theme.colorScheme.mutedForeground),
                  const SizedBox(width: 4),
                  const Text('清除时间'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // 重置按钮
          SizedBox(
            width: double.infinity,
            child: shadcn.OutlineButton(
              size: shadcn.ButtonSize.normal,
              onPressed: () {
                notifier.clearFilter();
                _searchController.clear();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(shadcn.LucideIcons.rotateCcw, size: 14, color: theme.colorScheme.foreground),
                  const SizedBox(width: 8),
                  const Text('重置筛选'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, shadcn.ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.mutedForeground,
        letterSpacing: 0.5,
      ),
    );
  }

  List<Widget> _buildLevelCheckboxes(LogViewerState state, LogViewerNotifier notifier, shadcn.ThemeData theme) {
    const levels = ['INFO', 'WARN', 'ERROR'];
    return levels.map((level) {
      final isSelected = state.filter.levels.isEmpty || state.filter.levels.contains(level);
      final color = _getLevelColor(level);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: () => notifier.toggleLevel(level),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.border,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: isSelected
                      ? Icon(shadcn.LucideIcons.check, size: 12, color: theme.colorScheme.primaryForeground)
                      : null,
                ),
                const SizedBox(width: 10),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  level,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildMobileFilterBar(shadcn.ThemeData theme, bool isDark, LogViewerState state) {
    final notifier = ref.read(logViewerProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 搜索框
          Row(
            children: [
              Icon(
                shadcn.LucideIcons.search,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: shadcn.TextField(
                  controller: _searchController,
                  placeholder: const Text('搜索日志...'),
                  onChanged: (value) => notifier.setKeyword(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Level & Tag
          Row(
            children: [
              Expanded(
                child: shadcn.MultiSelect<String>(
                  value: state.filter.levels.toList(),
                  placeholder: const Text('级别'),
                  itemBuilder: (context, item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _getLevelColor(item),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(item, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  onChanged: (values) => notifier.setLevels(values?.toSet() ?? {}),
                  popup: shadcn.SelectPopup(
                    items: shadcn.SelectItemList(
                      children: ['INFO', 'WARN', 'ERROR']
                          .map((level) => shadcn.SelectItemButton(
                                value: level,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _getLevelColor(level),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(level),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: shadcn.Select<String?>(
                  value: state.filter.tag,
                  placeholder: const Text('标签'),
                  itemBuilder: (context, item) => Text(
                    item ?? '全部',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (value) => notifier.setTag(value),
                  popup: shadcn.SelectPopup(
                    items: shadcn.SelectItemList(
                      children: [
                        shadcn.SelectItemButton(value: null, child: const Text('全部')),
                        ...state.allTags.map((tag) => shadcn.SelectItemButton(value: tag, child: Text(tag))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Date & Reset
          Row(
            children: [
              Expanded(
                child: shadcn.DateRangePicker(
                  value: state.filter.startDate != null && state.filter.endDate != null
                      ? shadcn.DateTimeRange(state.filter.startDate!, state.filter.endDate!)
                      : null,
                  placeholder: const Text('时间', style: TextStyle(fontSize: 12)),
                  mode: shadcn.PromptMode.dialog,
                  onChanged: (range) {
                    if (range != null) {
                      notifier.setDateRange(range.start, range.end);
                    } else {
                      notifier.setDateRange(null, null);
                    }
                  },
                  stateBuilder: (date) => date.isAfter(DateTime.now())
                      ? shadcn.DateState.disabled
                      : shadcn.DateState.enabled,
                ),
              ),
              const SizedBox(width: 8),
              shadcn.OutlineButton(
                size: shadcn.ButtonSize.small,
                onPressed: () {
                  notifier.clearFilter();
                  _searchController.clear();
                },
                child: const Text('重置', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyLogs() async {
    try {
      final path = await LogService.instance.getLogPath();
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已复制到剪贴板')),
        );
      }
    } catch (_) {}
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _LogEntryCard extends StatefulWidget {
  final LogEntry entry;
  final shadcn.ThemeData theme;

  const _LogEntryCard({required this.entry, required this.theme});

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final entry = widget.entry;
    final levelColor = _getLevelColor(entry.level);
    final timeStr = DateFormat('MM-dd HH:mm:ss').format(entry.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: shadcn.Card(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(theme.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Level badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: levelColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.level,
                        style: TextStyle(
                          color: levelColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tag badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.tag,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Timestamp
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? shadcn.LucideIcons.chevronUp : shadcn.LucideIcons.chevronDown,
                      size: 14,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  entry.message,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
