import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';

class OverviewScreen extends StatelessWidget {
  final String title;
  final String overview;

  const OverviewScreen({super.key, required this.title, required this.overview});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: kAppBackButtonWidth,
        leading: AppBackButton(onPressed: () => context.pop(), color: Colors.black),
        title: Text(title, style: const TextStyle(color: Colors.black, fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          overview,
          style: TextStyle(color: Colors.black.withValues(alpha: 0.8), fontSize: 15, height: 1.8),
        ),
      ),
    );
  }
}
