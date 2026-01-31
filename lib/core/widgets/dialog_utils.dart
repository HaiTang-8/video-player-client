import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../providers/window_border_provider.dart';
import 'password_text_field.dart';

/// 弹窗工具类 - 使用 shadcn_flutter 组件
class DialogUtils {
  DialogUtils._();

  /// 显示确认对话框
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    // 允许调用方传入自定义内容（例如带滚动区域的文本），以满足长内容展示需求
    Widget? contentWidget,
    String cancelText = '取消',
    String confirmText = '确定',
    bool isDestructive = false,
    bool barrierDismissible = false,
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    try {
      return await shadcn.showDialog<bool>(
        context: context,
        // 控制是否允许点击遮罩层关闭，用于必须做出选择的场景
        barrierDismissible: barrierDismissible,
        builder: (context) {
          final theme = shadcn.Theme.of(context);
          // shadcn_flutter 的 destructive 默认会用较低 alpha（0.5），在弹窗里看起来像“灰色遮罩”。
          // 这里把默认/hover/focus 的背景都改成不透明 destructive 色，避免鼠标移入移出时颜色突变。
          final destructiveStyle = shadcn.ButtonVariance.destructive.withBackgroundColor(
            color: theme.colorScheme.destructive,
            hoverColor: theme.colorScheme.destructive,
            focusColor: theme.colorScheme.destructive,
          );

          return shadcn.AlertDialog(
            title: Text(title),
            // 优先使用自定义内容组件，未提供时回退为纯文本
            content: contentWidget ?? Text(content),
            actions: [
              shadcn.OutlineButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelText),
              ),
              if (isDestructive)
                shadcn.Button.destructive(
                  style: destructiveStyle,
                  disableFocusOutline: true,
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmText),
                )
              else
                shadcn.PrimaryButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmText),
                ),
            ],
          );
        },
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
    final theme = shadcn.Theme.of(context);

    shadcn.showToast(
      context: context,
      builder: (context, overlay) => Container(
        width: 320,
        margin: const EdgeInsets.only(top: 32),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isError
                  ? shadcn.LucideIcons.circleAlert
                  : shadcn.LucideIcons.circleCheck,
              size: 20,
              color: isError
                  ? theme.colorScheme.destructive
                  : const Color(0xFF16A34A),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.typography.small.copyWith(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            shadcn.GhostButton(
              size: shadcn.ButtonSize.xSmall,
              density: shadcn.ButtonDensity.icon,
              onPressed: overlay.close,
              child: Icon(
                shadcn.LucideIcons.x,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      location: shadcn.ToastLocation.topCenter,
      showDuration: const Duration(seconds: 2),
    );
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
        barrierDismissible: false,
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
    bool obscureText = false,
    double maxWidth = 400,
    int? maxLength,
  }) async {
    final container = ProviderScope.containerOf(context);
    container.read(windowBorderVisibleProvider.notifier).hide();
    final controller = TextEditingController(text: initialValue);
    try {
      return await shadcn.showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => shadcn.AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: maxWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: obscureText
                  ? PasswordTextField(
                      controller: controller,
                      placeholder: placeholder != null ? Text(placeholder) : null,
                      autofocus: true,
                      maxLength: maxLength,
                    )
                  : shadcn.TextField(
                      controller: controller,
                      placeholder: placeholder != null ? Text(placeholder) : null,
                      keyboardType: keyboardType,
                      autofocus: true,
                      inputFormatters: maxLength != null
                          ? [LengthLimitingTextInputFormatter(maxLength)]
                          : null,
                    ),
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
