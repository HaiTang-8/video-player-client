import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final errorNotificationProvider = StateNotifierProvider<ErrorNotificationNotifier, String?>((ref) {
  return ErrorNotificationNotifier();
});

class ErrorNotificationNotifier extends StateNotifier<String?> {
  ErrorNotificationNotifier() : super(null);

  void notify(String message) {
    state = message;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) state = null;
    });
  }
}
