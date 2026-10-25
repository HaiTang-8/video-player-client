import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../window/window_controls.dart';
import 'desktop_app_bar.dart';
import 'mobile_app_bar.dart';

const double _maxFormWidth = 640;

/// 表单页骨架：标题栏 + 居中限宽内容 + 底部固定操作区
class FormPageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? bottomAction;

  const FormPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.bottomAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar:
          WindowControls.isDesktop
              ? DesktopAppBar(title: Text(title), onBack: () => context.pop())
              : MobileAppBar(title: Text(title), onBack: () => context.pop()),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = ((constraints.maxWidth - _maxFormWidth) / 2).clamp(
            16.0,
            double.infinity,
          );
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 24),
            children: children,
          );
        },
      ),
      bottomNavigationBar:
          bottomAction == null
              ? null
              : DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  border: Border(
                    top: BorderSide(color: colors.divider, width: 0.5),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _maxFormWidth - 32,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: bottomAction,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
    );
  }
}

/// 分组：标题 + 卡片
class FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FormSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 带标签的表单项
class FormFieldBlock extends StatelessWidget {
  final String label;
  final Widget child;
  final String? helper;

  const FormFieldBlock({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        child,
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 页内结果提示（替代弹窗反馈）
class FormNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const FormNotice({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

/// 可选中的选项卡片
class FormOptionCard extends StatelessWidget {
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final CrossAxisAlignment alignment;

  const FormOptionCard({
    super.key,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: selected ? color.withValues(alpha: 0.1) : colors.cardBackgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(color: colors.textPrimary),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
