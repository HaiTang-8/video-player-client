import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const double kAppBackButtonIconSize = 22;
const double kAppBackButtonLeftPadding = 12;
const double kAppBackButtonWidth =
    kAppBackButtonLeftPadding + kAppBackButtonIconSize;

class AppBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  final double iconSize;
  final double leftPadding;

  const AppBackButton({
    super.key,
    required this.onPressed,
    this.color,
    this.iconSize = kAppBackButtonIconSize,
    this.leftPadding = kAppBackButtonLeftPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: InkResponse(
        onTap: onPressed,
        radius: iconSize,
        child: Icon(CupertinoIcons.back, size: iconSize, color: color),
      ),
    );
  }
}
