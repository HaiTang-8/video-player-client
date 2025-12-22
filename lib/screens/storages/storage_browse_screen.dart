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

/// 存储源目录浏览页面（像资源管理器一样逐级进入）
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
      ref.read(browseProvider(widget.storageId).notifier).browse('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final browseState = ref.watch(browseProvider(widget.storageId));
    final title = widget.storage?.name ?? '目录浏览';
    final isDesktop = WindowControls.isDesktop;

    return PopScope(
      canPop: browseState.currentPath == '/',
      onPopInvokedWithResult: (didPop, result) {
        // Android/桌面返回键：优先“返回上级目录”，只有在根目录才退出页面
        if (didPop) return;
        ref.read(browseProvider(widget.storageId).notifier).goBack();
      },
      child: Scaffold(
        appBar:
            isDesktop
                ? DesktopTitleBar(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  // 与影视详情页保持一致：标题靠左，不居中
                  centerTitle: false,
                  leading: AppBackButton(
                    onPressed: () {
                      if (browseState.currentPath != '/') {
                        ref
                            .read(browseProvider(widget.storageId).notifier)
                            .goBack();
                        return;
                      }
                      context.pop();
                    },
                    color: Colors.black,
                  ),
                  title: Text(title),
                  actions: [
                    IconButton(
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        ref
                            .read(browseProvider(widget.storageId).notifier)
                            .browse(browseState.currentPath);
                      },
                    ),
                    IconButton(
                      tooltip: 'AI 整理当前目录',
                      icon: const Icon(Icons.auto_fix_high),
                      onPressed: () => _startAiTidy(browseState.currentPath),
                    ),
                  ],
                )
                : AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  toolbarHeight: 44,
                  // 与影视详情页保持一致：返回按钮用“<”样式，标题靠左（避免 iOS 默认居中）
                  centerTitle: false,
                  automaticallyImplyLeading: false,
                  leadingWidth: kAppBackButtonWidth,
                  titleSpacing: 1,
                  leading: AppBackButton(
                    onPressed: () {
                      if (browseState.currentPath != '/') {
                        ref
                            .read(browseProvider(widget.storageId).notifier)
                            .goBack();
                        return;
                      }
                      context.pop();
                    },
                    color: Colors.black,
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: '刷新',
                      icon: const Icon(
                        Icons.refresh,
                        color: Colors.black,
                        size: 20,
                      ),
                      onPressed: () {
                        ref
                            .read(browseProvider(widget.storageId).notifier)
                            .browse(browseState.currentPath);
                      },
                    ),
                    IconButton(
                      tooltip: 'AI 整理当前目录',
                      icon: const Icon(
                        Icons.auto_fix_high,
                        color: Colors.black,
                        size: 20,
                      ),
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
            const Divider(height: 1),
            Expanded(child: _buildBody(context, browseState)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BrowseState state) {
    if (state.isLoading && state.files.isEmpty) {
      return const LoadingWidget(message: '加载中...');
    }

    if (state.error != null && state.files.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry:
            () => ref
                .read(browseProvider(widget.storageId).notifier)
                .browse(state.currentPath),
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
        icon: Icons.folder_off_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(browseProvider(widget.storageId).notifier)
            .browse(state.currentPath);
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: Icon(item.isDir ? Icons.folder : Icons.insert_drive_file),
            title: Text(item.name),
            subtitle:
                item.isDir
                    ? null
                    : Text(
                      [
                        if (item.formattedSize.isNotEmpty) item.formattedSize,
                        if (item.modTime != null)
                          item.modTime!.toLocal().toString(),
                      ].where((e) => e.isNotEmpty).join(' · '),
                    ),
            trailing: item.isDir ? const Icon(Icons.chevron_right) : null,
            onTap: () async {
              if (item.isDir) {
                await ref
                    .read(browseProvider(widget.storageId).notifier)
                    .enterDirectory(item.name);
              } else {
                await _showFileInfo(context, item);
              }
            },
            onLongPress: () => _copyToClipboard(context, item.path),
          );
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
        builder:
            (_) => AiTidyPreviewScreen(
              storageId: widget.storageId,
              rootPath: currentPath,
              maxFiles: selected,
            ),
      ),
    );

    if (!mounted) return;
    if (applied == true) {
      await ref
          .read(browseProvider(widget.storageId).notifier)
          .browse(currentPath);
    }
  }

  Future<void> _showFileInfo(BuildContext context, FileInfo file) async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('文件信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('名称：${file.name}'),
                const SizedBox(height: 8),
                Text('路径：${file.path}'),
                const SizedBox(height: 8),
                if (file.formattedSize.isNotEmpty)
                  Text('大小：${file.formattedSize}'),
                if (file.modTime != null) ...[
                  const SizedBox(height: 8),
                  Text('修改时间：${file.modTime!.toLocal()}'),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _copyToClipboard(context, file.path);
                },
                child: const Text('复制路径'),
              ),
            ],
          ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制：$text')));
  }
}

class _PathBar extends StatelessWidget {
  final String path;
  final VoidCallback onCopy;

  const _PathBar({required this.path, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: '复制当前路径',
              onPressed: onCopy,
              icon: const Icon(Icons.content_copy, size: 18),
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
    return AlertDialog(
      title: const Text('AI 整理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将对以下目录（含子目录）生成整理建议：\n${widget.path}'),
          const SizedBox(height: 16),
          const Text('最大分析文件数（目录过大时可降低或分目录整理）：'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _maxFiles,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 200, child: Text('200')),
              DropdownMenuItem(value: 500, child: Text('500（推荐）')),
              DropdownMenuItem(value: 1000, child: Text('1000')),
              DropdownMenuItem(value: 2000, child: Text('2000（最大）')),
            ],
            onChanged: (value) => setState(() => _maxFiles = value ?? 500),
          ),
          const SizedBox(height: 12),
          const Text(
            '提示：此步骤只生成预览方案，不会修改任何文件；应用时会再次要求你确认。',
            style: TextStyle(fontSize: 12),
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
