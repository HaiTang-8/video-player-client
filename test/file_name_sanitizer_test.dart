import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/utils/file_name_sanitizer.dart';

void main() {
  group('sanitizeFileName', () {
    test('replaces Windows-illegal characters', () {
      expect(sanitizeFileName('a<b>c:"d/e\\\\f|g?*h'), 'a_b_c__d_e__f_g__h');
    });

    test('trims trailing dots and spaces', () {
      expect(sanitizeFileName('abc. '), 'abc');
      expect(sanitizeFileName('abc...   '), 'abc');
    });

    test('prefixes Windows reserved device names (case-insensitive)', () {
      expect(sanitizeFileName('con'), '_con');
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('lpt1'), '_lpt1');
    });

    test('returns fallback name when empty after sanitization', () {
      expect(sanitizeFileName('   '), 'file');
      expect(sanitizeFileName('..'), 'file');
    });
  });
}

