import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_back_button.dart';

class OverviewScreen extends StatelessWidget {
  final String title;
  final String overview;

  const OverviewScreen({super.key, required this.title, required this.overview});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.cardBackground,
      appBar: AppBar(
        backgroundColor: colors.cardBackground,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: kAppBackButtonWidth,
        leading: AppBackButton(onPressed: () => context.pop(), color: colors.textPrimary),
        title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          overview,
          style: TextStyle(color: colors.textPrimary.withValues(alpha: 0.8), fontSize: 15, height: 1.8),
        ),
      ),
    );
  }
}
