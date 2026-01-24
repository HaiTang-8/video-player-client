import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../providers/window_border_provider.dart';

/// 弹窗工具类 - 使用 shadcn_flutter 组件
class DialogUtils {
  DialogUtils._();

  /// 显示确认对话框
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String cancelText = '取消',
    String confirmText = '确定',
    bool isDestructive = false,
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    try {
      return await shadcn.showDialog<bool>(
        context: context,
        builder: (context) => shadcn.AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            shadcn.OutlineButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancelText),
            ),
            if (isDestructive)
              shadcn.DestructiveButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              )
            else
              shadcn.PrimaryButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
          ],
        ),
      );
    } finally {
      container.read(windowBorderVisibleProvider.notifier).show();
    }
  }

  /// 显示加载对话框
  static Future<void> showLoadingDialog({
    required BuildContext context,
    required String message,
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    try {
      return await shadcn.showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => shadcn.AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const shadcn.CircularProgressIndicator(),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      );
    } finally {
      container.read(windowBorderVisibleProvider.notifier).show();
    }
  }

  /// 显示 Toast 提示
  static void showToast({
    required BuildContext context,
    required String message,
    bool isError = false,
  }) {
    final overlay = Overlay.of(context);
    _insertToast(overlay, message, isError);
  }

  static void showToastWithOverlay({
    required OverlayState overlay,
    required String message,
    bool isError = false,
  }) {
    _insertToast(overlay, message, isError);
  }

  static void _insertToast(OverlayState overlay, String message, bool isError) {
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        isError: isError,
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  /// 显示选择器对话框
  static Future<T?> showSelectionDialog<T>({
    required BuildContext context,
    required String title,
    required List<SelectionOption<T>> options,
    T? currentValue,
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    try {
      return await shadcn.showDialog<T>(
        context: context,
        builder: (context) => shadcn.AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((option) {
              final isSelected = option.value == currentValue;
              return InkWell(
                onTap: () => Navigator.pop(context, option.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(option.label)),
                      if (isSelected)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            shadcn.OutlineButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    } finally {
      container.read(windowBorderVisibleProvider.notifier).show();
    }
  }

  /// 显示输入对话框
  static Future<String?> showInputDialog({
    required BuildContext context,
    required String title,
    String? placeholder,
    String? initialValue,
    TextInputType? keyboardType,
    String cancelText = '取消',
    String confirmText = '确定',
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    final controller = TextEditingController(text: initialValue);
    try {
      return await shadcn.showDialog<String>(
        context: context,
        builder: (context) => shadcn.AlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: shadcn.TextField(
              controller: controller,
              placeholder: placeholder != null ? Text(placeholder) : null,
              keyboardType: keyboardType,
              autofocus: true,
            ),
          ),
          actions: [
            shadcn.OutlineButton(
              onPressed: () => Navigator.pop(context),
              child: Text(cancelText),
            ),
            shadcn.PrimaryButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(confirmText),
            ),
          ],
        ),
      );
    } finally {
      container.read(windowBorderVisibleProvider.notifier).show();
    }
  }
}

/// 选项
class SelectionOption<T> {
  final T value;
  final String label;

  const SelectionOption({required this.value, required this.label});
}

/// Toast Widget
class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;

  const _ToastWidget({
    required this.message,
    this.isError = false,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final isDark = theme.colorScheme.brightness == Brightness.dark;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.isError
                      ? Colors.red.withValues(alpha: 0.9)
                      : (isDark
                          ? Colors.grey[800]!.withValues(alpha: 0.95)
                          : Colors.grey[700]!.withValues(alpha: 0.95)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
