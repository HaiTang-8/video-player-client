import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/smooth_scroll_behavior.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'ai_tidy_preview_screen.dart';
import 'blacklist_manager_dialog.dart';

class StorageBrowseScreen extends ConsumerStatefulWidget {
  final int storageId;
  final Storage? storage;

  const StorageBrowseScreen({super.key, required this.storageId, this.storage});

  @override
  ConsumerState<StorageBrowseScreen> createState() =>
      _StorageBrowseScreenState();
}

class _StorageBrowseScreenState extends ConsumerState<StorageBrowseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      browseStorage(ref, widget.storageId, '/');
      loadBlacklist(ref, widget.storageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final browseState = ref.watch(browseProvider(widget.storageId));
    final storageName = widget.storage?.name ?? '目录浏览';
    final title =
        browseState.currentPath == '/'
            ? storageName
            : browseState.currentPath.split('/').last;
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);

    return PopScope(
      canPop: browseState.currentPath == '/',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        goBackDirectory(ref, widget.storageId);
      },
      child: Scaffold(
        appBar:
            isDesktop
                ? DesktopAppBar(
                  title: Text(title),
                  onBack: () {
                    if (browseState.currentPath != '/') {
                      goBackDirectory(ref, widget.storageId);
                      return;
                    }
                    context.pop();
                  },
                  actions: [
                    IconButton(
                      tooltip: '刷新',
                      icon: const Icon(CupertinoIcons.refresh),
                      onPressed: () {
                        browseStorage(
                          ref,
                          widget.storageId,
                          browseState.currentPath,
                        );
                      },
                    ),
                    IconButton(
                      tooltip: '黑名单管理',
                      icon: const Icon(CupertinoIcons.nosign),
                      onPressed: () => _showBlacklistManager(),
                    ),
                    IconButton(
                      tooltip: 'AI 整理当前目录',
                      icon: const Icon(CupertinoIcons.wand_stars),
                      onPressed: () => _startAiTidy(browseState.currentPath),
                    ),
                  ],
                )
                : MobileAppBar(
                  title: Text(title),
                  onBack: () {
                    if (browseState.currentPath != '/') {
                      goBackDirectory(ref, widget.storageId);
                      return;
                    }
                    context.pop();
                  },
                  actions: [
                    IconButton(
                      tooltip: '刷新',
                      icon: const Icon(CupertinoIcons.refresh, size: 20),
                      onPressed: () {
                        browseStorage(
                          ref,
                          widget.storageId,
                          browseState.currentPath,
                        );
                      },
                    ),
                    IconButton(
                      tooltip: '黑名单管理',
                      icon: const Icon(CupertinoIcons.nosign, size: 20),
                      onPressed: () => _showBlacklistManager(),
                    ),
                    IconButton(
                      tooltip: 'AI 整理当前目录',
                      icon: const Icon(CupertinoIcons.wand_stars, size: 20),
                      onPressed: () => _startAiTidy(browseState.currentPath),
                    ),
                  ],
                ),
        body: Column(
          children: [
            _PathBar(
              path: browseState.currentPath,
              onCopy: () => _copyToClipboard(context, browseState.currentPath),
            ),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
            Expanded(child: _buildBody(context, browseState)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BrowseState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (state.isLoading && state.files.isEmpty) {
      return const ListSkeletonLoader();
    }

    if (state.error != null && state.files.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => browseStorage(ref, widget.storageId, state.currentPath),
      );
    }

    final items = [...state.files];
    items.sort((a, b) {
      if (a.isDir != b.isDir) {
        return a.isDir ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (items.isEmpty) {
      return const EmptyWidget(message: '该目录为空', icon: CupertinoIcons.folder);
    }

    return DesktopSmoothScroll(
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await browseStorage(ref, widget.storageId, state.currentPath);
            },
            child: ListView.builder(
              primary: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          _FileTile(
                            file: items[i],
                            isBlacklisted: state.isBlacklisted(items[i].path),
                            onTap: () async {
                              if (items[i].isDir) {
                                await enterDirectory(
                                  ref,
                                  widget.storageId,
                                  items[i].name,
                                );
                              } else {
                                await _showFileInfo(context, items[i]);
                              }
                            },
                            onLongPress:
                                () =>
                                    _showContextMenu(context, items[i], state),
                          ),
                          if (i < items.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 60),
                              child: Divider(
                                height: 1,
                                thickness: 0.5,
                                color: theme.dividerColor.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          if (state.isLoading)
            Positioned.fill(
              child: Container(
                color: isDark ? Colors.black54 : Colors.white54,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startAiTidy(String currentPath) async {
    final selected =
        await showDialog<({int maxFiles, bool enableTmdb, String folderMode})>(
          context: context,
          builder: (context) => _AiTidyStartDialog(path: currentPath),
        );
    if (!mounted) return;
    if (selected == null) return;

    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => AiTidyPreviewScreen(
              storageId: widget.storageId,
              rootPath: currentPath,
              maxFiles: selected.maxFiles,
              enableTmdb: selected.enableTmdb,
              folderMode: selected.folderMode,
            ),
      ),
    );

    if (!mounted) return;
    if (applied == true) {
      await browseStorage(ref, widget.storageId, currentPath);
    }
  }

  Future<void> _showFileInfo(BuildContext context, FileInfo file) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          CupertinoIcons.doc,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          file.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInfoRow(theme, '路径', file.path),
                  if (file.formattedSize.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(theme, '大小', file.formattedSize),
                  ],
                  if (file.modTime != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      theme,
                      '修改时间',
                      file.modTime!.toLocal().toString(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _copyToClipboard(context, file.path);
                      },
                      icon: const Icon(CupertinoIcons.doc_on_clipboard),
                      label: const Text('复制路径'),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    DialogUtils.showToast(context: context, message: '已复制');
  }

  void _showBlacklistManager() {
    showDialog(
      context: context,
      builder: (context) => BlacklistManagerDialog(storageId: widget.storageId),
    );
  }

  void _showContextMenu(
    BuildContext context,
    FileInfo file,
    BrowseState state,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBlacklisted = state.isBlacklisted(file.path);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    file.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_clipboard),
                  title: const Text('复制路径'),
                  onTap: () {
                    Navigator.pop(context);
                    _copyToClipboard(context, file.path);
                  },
                ),
                if (file.isDir)
                  ListTile(
                    leading: Icon(
                      isBlacklisted
                          ? CupertinoIcons.checkmark_circle
                          : CupertinoIcons.nosign,
                      color: isBlacklisted ? Colors.green : Colors.orange,
                    ),
                    title: Text(isBlacklisted ? '从黑名单移除' : '添加到黑名单'),
                    subtitle: Text(
                      isBlacklisted ? '恢复扫描此目录' : '扫描时跳过此目录',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final success =
                          isBlacklisted
                              ? await removeFromBlacklist(
                                ref,
                                widget.storageId,
                                file.path,
                              )
                              : await addToBlacklist(
                                ref,
                                widget.storageId,
                                file.path,
                              );
                      if (!mounted || !success) return;
                      DialogUtils.showToast(
                        context: this.context,
                        message: isBlacklisted ? '已从黑名单移除' : '已添加到黑名单',
                      );
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final FileInfo file;
  final bool isBlacklisted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileTile({
    required this.file,
    required this.isBlacklisted,
    required this.onTap,
    required this.onLongPress,
  });

  static const _videoExtensions = {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'ts',
    'rmvb',
    'rm',
    '3gp',
    'mpg',
    'mpeg',
    'vob',
  };

  bool get _isVideo {
    final ext = file.name.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color iconColor;
    final IconData iconData;

    if (isBlacklisted) {
      iconColor = Colors.grey;
      iconData = CupertinoIcons.nosign;
    } else if (file.isDir) {
      iconColor = Colors.blue;
      iconData = CupertinoIcons.folder;
    } else if (_isVideo) {
      iconColor = Colors.purple;
      iconData = CupertinoIcons.play_rectangle_fill;
    } else {
      iconColor = Colors.grey;
      iconData = CupertinoIcons.doc;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                child: Icon(iconData, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            file.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: isBlacklisted ? Colors.grey : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBlacklisted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '已禁用',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!file.isDir && file.formattedSize.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        file.formattedSize,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (file.isDir)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathBar extends StatelessWidget {
  final String path;
  final VoidCallback onCopy;

  const _PathBar({required this.path, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.folder,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            GestureDetector(
              onTap: onCopy,
              child: Icon(
                CupertinoIcons.doc_on_clipboard,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiTidyStartDialog extends StatefulWidget {
  final String path;

  const _AiTidyStartDialog({required this.path});

  @override
  State<_AiTidyStartDialog> createState() => _AiTidyStartDialogState();
}

class _AiTidyStartDialogState extends State<_AiTidyStartDialog> {
  int _maxFiles = 500;
  bool _enableTmdb = true;
  String _folderMode = 'subfolder';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(CupertinoIcons.wand_stars, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('AI 整理'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将对以下目录（含子目录）生成整理建议：', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.path,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('电影整理模式：', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _folderMode,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'subfolder', child: Text('创建子文件夹')),
                DropdownMenuItem(value: 'rename_file', child: Text('仅重命名文件')),
                DropdownMenuItem(value: 'rename_dir', child: Text('重命名父文件夹')),
              ],
              onChanged:
                  (value) => setState(() => _folderMode = value ?? 'subfolder'),
            ),
            const SizedBox(height: 4),
            Text(
              _folderModeDescription(_folderMode),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('最大分析文件数：', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _maxFiles,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 200, child: Text('200')),
                DropdownMenuItem(value: 500, child: Text('500（推荐）')),
                DropdownMenuItem(value: 1000, child: Text('1000')),
                DropdownMenuItem(value: 2000, child: Text('2000（最大）')),
              ],
              onChanged: (value) => setState(() => _maxFiles = value ?? 500),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('使用 TMDB 辅助识别'),
              subtitle: Text(
                '从 TMDB 数据库获取准确的影视名称',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _enableTmdb,
              onChanged: (value) => setState(() => _enableTmdb = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              '提示：此步骤只生成预览方案，不会修改任何文件。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.pop(context, (
                maxFiles: _maxFiles,
                enableTmdb: _enableTmdb,
                folderMode: _folderMode,
              )),
          child: const Text('生成预览'),
        ),
      ],
    );
  }

  String _folderModeDescription(String mode) {
    switch (mode) {
      case 'rename_file':
        return '直接重命名文件，不创建子文件夹';
      case 'rename_dir':
        return '将父文件夹重命名为正确的影片名称';
      default:
        return '在当前目录下创建 "片名 (年份)" 子文件夹';
    }
  }
}
