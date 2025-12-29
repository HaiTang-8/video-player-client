import 'package:flutter/material.dart';
import 'app_back_button.dart';

class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final VoidCallback onBack;
  final List<Widget>? actions;

  const MobileAppBar({
    super.key,
    required this.title,
    required this.onBack,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      automaticallyImplyLeading: false,
      leadingWidth: kAppBackButtonWidth,
      leading: AppBackButton(onPressed: onBack),
      title: title,
      actions: actions,
    );
  }
}
