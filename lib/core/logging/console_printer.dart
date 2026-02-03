import 'dart:async';
import 'dart:io';

/// Centralized console output for the app.
///
/// Why this exists:
/// - Some outputs (e.g. child process progress) may contain `\r` or ANSI escapes,
///   which can make the terminal look like "overlapping layers".
/// - By intercepting `print()` via ZoneSpecification, we can sanitize output once
///   and keep the console readable.
class ConsolePrinter {
  static final ZoneSpecification zoneSpecification = ZoneSpecification(
    print: (self, parent, zone, line) {
      // Sanitize once and delegate to the real print implementation.
      parent.print(zone, ConsolePrinter.sanitize(line));
    },
  );

  static final RegExp _ansiCsi = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  static final RegExp _ansiOsc = RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)');
  static final RegExp _ansiSingle = RegExp(r'\x1B[@-Z\\-_]');
  static final RegExp _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  static void write(String message) {
    stdout.writeln(sanitize(message));
  }

  /// Sanitizes console text:
  /// - Converts CRLF/CR to LF (prevents line overwrite behavior).
  /// - Strips ANSI escape sequences (colors, cursor moves).
  /// - Applies backspaces.
  /// - Removes other control characters.
  static String sanitize(String input) {
    var s = input;
    s = s.replaceAll('\r\n', '\n');
    s = s.replaceAll('\r', '\n');

    // Strip ANSI escape sequences.
    s = s.replaceAll(_ansiOsc, '');
    s = s.replaceAll(_ansiCsi, '');
    s = s.replaceAll(_ansiSingle, '');

    // Apply backspaces to avoid visual corruption.
    s = _applyBackspaces(s);

    // Remove remaining control characters (keep \n and \t).
    s = s.replaceAll(_controlChars, '');
    return s;
  }

  static String _applyBackspaces(String input) {
    // Common in progress outputs: "abc\b\b\b123" to overwrite.
    final out = <int>[];
    for (final codeUnit in input.codeUnits) {
      if (codeUnit == 0x08) {
        // backspace
        if (out.isNotEmpty) {
          out.removeLast();
        }
        continue;
      }
      out.add(codeUnit);
    }
    return String.fromCharCodes(out);
  }
}
