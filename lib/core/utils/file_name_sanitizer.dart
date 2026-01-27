/// Cross-platform file name sanitization.
///
/// Notes:
/// - Replaces characters that are invalid on Windows with `_`.
/// - Trims trailing dots/spaces (invalid on Windows).
/// - Prefixes Windows reserved device names (CON, NUL, COM1, ...) with `_`.
String sanitizeFileName(String fileName) {
  // Replace control chars + Windows-forbidden characters.
  var name = fileName.replaceAll(RegExp(r'[\u0000-\u001F<>:"/\\|?*]'), '_');

  // Windows disallows trailing dots/spaces.
  name = name.replaceAll(RegExp(r'[ .]+$'), '');

  if (name.isEmpty) return 'file';

  // Windows reserved device names are invalid even with extensions (including multi-extension),
  // so we check the first component before the first dot.
  final firstComponent = name.split('.').first;
  const reserved = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  if (reserved.contains(firstComponent.toUpperCase()) || name == '.' || name == '..') {
    name = '_$name';
  }

  return name;
}
