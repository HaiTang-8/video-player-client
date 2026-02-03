import 'package:test/test.dart';
import 'package:media_player/core/logging/console_printer.dart';

void main() {
  group('ConsolePrinter.sanitize', () {
    test('converts CRLF/CR to LF', () {
      expect(ConsolePrinter.sanitize('a\r\nb'), 'a\nb');
      expect(ConsolePrinter.sanitize('a\rb'), 'a\nb');
    });

    test('strips ANSI escape sequences', () {
      expect(ConsolePrinter.sanitize('\x1B[31mred\x1B[0m'), 'red');
    });

    test('applies backspaces', () {
      expect(ConsolePrinter.sanitize('abc\b\bde'), 'ade');
    });

    test('removes other control characters but keeps unicode text', () {
      expect(ConsolePrinter.sanitize('⛔ API Error: 网络错误\x07'), '⛔ API Error: 网络错误');
    });
  });
}
