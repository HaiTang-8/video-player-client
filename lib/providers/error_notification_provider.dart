import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final errorNotificationProvider = NotifierProvider<ErrorNotificationNotifier, String?>(ErrorNotificationNotifier.new);

class ErrorNotificationNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void notify(String message) {
    state = message;
    Future.delayed(const Duration(milliseconds: 100), () {
      state = null;
    });
  }
}
