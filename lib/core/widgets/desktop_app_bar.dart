import 'package:flutter/material.dart';
import 'app_back_button.dart';
import 'desktop_title_bar.dart';

class DesktopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final VoidCallback onBack;
  final List<Widget> actions;

  const DesktopAppBar({
    super.key,
    required this.title,
    required this.onBack,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return DesktopTitleBar(
      centerTitle: false,
      leading: AppBackButton(onPressed: onBack),
      title: title,
      actions: actions,
    );
  }
}
