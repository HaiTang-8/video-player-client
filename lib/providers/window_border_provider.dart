import 'package:flutter_riverpod/flutter_riverpod.dart';

final windowBorderVisibleProvider =
    NotifierProvider<WindowBorderNotifier, bool>(WindowBorderNotifier.new);

class WindowBorderNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void hide() => state = false;
  void show() => state = true;
}
