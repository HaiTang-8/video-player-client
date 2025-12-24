import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'ai_tidy_preview_screen.dart';

class StorageBrowseScreen extends ConsumerStatefulWidget {
  final int storageId;
  final Storage? storage;

  const StorageBrowseScreen({super.key, required this.storageId, this.storage});

  @override
  ConsumerState<StorageBrowseScreen> createState() => _StorageBrowseScreenState();
}

class _StorageBrowseScreenState extends ConsumerState<StorageBrowseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(browseProvider(widget.storageId).notifier).browse('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final browseState = ref.watch(browseProvider(widget.storageId));
    final title = widget.storage?.name ?? '目录浏览';
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);

    return PopScope(
      canPop: browseState.currentPath == '/',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(browseProvider(widget.storageId).notifier).goBack();
      },
      child: Scaffold(
        appBar: isDesktop
            ? DesktopTitleBar(
                centerTitle: false,
                leading: AppBackButton(
                  onPressed: () {
                    if (browseState.currentPath != '/') {
                      ref.read(browseProvider(widget.storageId).notifier).goBack();
                      return;
                    }
                    context.pop();
                  },
                ),
                title: Text(title),
                actions: [
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(CupertinoIcons.refresh),
                    onPressed: () {
                      ref.read(browseProvider(widget.storageId).notifier).browse(browseState.currentPath);
                    },
                  ),
                  IconButton(
                    tooltip: 'AI 整理当前目录',
                    icon: const Icon(CupertinoIcons.wand_stars),
                    onPressed: () => _startAiTidy(browseState.currentPath),
                  ),
                ],
              )
            : AppBar(
                elevation: 0,
                toolbarHeight: 44,
                centerTitle: false,
                automaticallyImplyLeading: false,
                leadingWidth: kAppBackButtonWidth,
                titleSpacing: 1,
                leading: AppBackButton(
                  onPressed: () {
                    if (browseState.currentPath != '/') {
                      ref.read(browseProvider(widget.storageId).notifier).goBack();
                      return;
                    }
                    context.pop();
                  },
                ),
                title: Text(title),
                actions: [
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(CupertinoIcons.refresh, size: 20),
                    onPressed: () {
                      ref.read(browseProvider(widget.storageId).notifier).browse(browseState.currentPath);
                    },
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
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
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
      return const LoadingWidget(message: '加载中...');
    }

    if (state.error != null && state.files.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(browseProvider(widget.storageId).notifier).browse(state.currentPath),
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
      return const EmptyWidget(
        message: '该目录为空',
        icon: CupertinoIcons.folder,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(browseProvider(widget.storageId).notifier).browse(state.currentPath);
      },
      child: ListView.builder(
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
                      onTap: () async {
                        if (items[i].isDir) {
                          await ref.read(browseProvider(widget.storageId).notifier).enterDirectory(items[i].name);
                        } else {
                          await _showFileInfo(context, items[i]);
                        }
                      },
                      onLongPress: () => _copyToClipboard(context, items[i].path),
                    ),
                    if (i < items.length - 1)
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
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _startAiTidy(String currentPath) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _AiTidyStartDialog(path: currentPath),
    );
    if (!mounted) return;
    if (selected == null) return;

    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AiTidyPreviewScreen(
          storageId: widget.storageId,
          rootPath: currentPath,
          maxFiles: selected,
        ),
      ),
    );

    if (!mounted) return;
    if (applied == true) {
      await ref.read(browseProvider(widget.storageId).notifier).browse(currentPath);
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
      builder: (context) => SafeArea(
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
                    child: const Icon(CupertinoIcons.doc, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      file.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
                _buildInfoRow(theme, '修改时间', file.modTime!.toLocal().toString()),
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
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：$text')),
    );
  }
}

class _FileTile extends StatelessWidget {
  final FileInfo file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = file.isDir ? Colors.blue : Colors.grey;

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
                child: Icon(
                  file.isDir ? CupertinoIcons.folder : CupertinoIcons.doc,
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
                      file.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将对以下目录（含子目录）生成整理建议：',
            style: theme.textTheme.bodyMedium,
          ),
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
          Text(
            '最大分析文件数：',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _maxFiles,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 200, child: Text('200')),
              DropdownMenuItem(value: 500, child: Text('500（推荐）')),
              DropdownMenuItem(value: 1000, child: Text('1000')),
              DropdownMenuItem(value: 2000, child: Text('2000（最大）')),
            ],
            onChanged: (value) => setState(() => _maxFiles = value ?? 500),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：此步骤只生成预览方案，不会修改任何文件。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _maxFiles),
          child: const Text('生成预览'),
        ),
      ],
    );
  }
}
