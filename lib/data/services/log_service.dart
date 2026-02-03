import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/log_entry.dart';

class LogService {
  static LogService? _instance;
  static LogService get instance => _instance ??= LogService._();

  LogService._();

  File? _logFile;
  IOSink? _sink;
  static const int _maxLogSize = 5 * 1024 * 1024; // 5MB

  static final RegExp _ansiCsi = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  static final RegExp _ansiOsc = RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)');
  static final RegExp _ansiSingle = RegExp(r'\x1B[@-Z\\-_]');
  static final RegExp _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  // 日志级别：debug < info < warn < error
  static const _levelPriority = {'DEBUG': 0, 'INFO': 1, 'WARN': 2, 'ERROR': 3};
  final String _minLevel = kDebugMode ? 'DEBUG' : 'INFO';

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}/player.log');
      await _rotateIfNeeded();
      _sink = _logFile!.openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('[LogService] init failed: $e');
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    final stat = await _logFile!.stat();
    if (stat.size > _maxLogSize) {
      final backupFile = File('${_logFile!.path}.old');
      if (await backupFile.exists()) await backupFile.delete();
      await _logFile!.rename(backupFile.path);
      _logFile = File(_logFile!.path);
    }
  }

  void log(String level, String tag, String message, {bool printToConsole = kDebugMode}) {
    final upperLevel = level.toUpperCase();
    final minPriority = _levelPriority[_minLevel] ?? 1;
    final currentPriority = _levelPriority[upperLevel] ?? 1;
    if (currentPriority < minPriority) return;

    final safeTag = _sanitizeSingleLine(tag);
    final safeMessage = _sanitizeSingleLine(message);

    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$upperLevel] [$safeTag] $safeMessage\n';
    if (printToConsole) debugPrint(line.trimRight());
    _sink?.write(line);
  }

  void debug(String tag, String message) => log('DEBUG', tag, message);
  void info(String tag, String message) => log('INFO', tag, message);
  void warn(String tag, String message) => log('WARN', tag, message);
  void error(String tag, String message) => log('ERROR', tag, message);

  Future<void> flush() async => await _sink?.flush();

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  Future<String?> getLogPath() async {
    if (_logFile != null) return _logFile!.path;
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/logs/player.log';
    } catch (_) {
      return null;
    }
  }

  Future<List<LogEntry>> readLogs() async {
    await flush();
    final entries = <LogEntry>[];
    try {
      final path = await getLogPath();
      if (path == null) return entries;

      final file = File(path);
      if (!await file.exists()) return entries;

      final lines = await file.readAsLines();
      for (final line in lines) {
        final entry = LogEntry.parse(line);
        if (entry != null) entries.add(entry);
      }
    } catch (e) {
      debugPrint('[LogService] readLogs failed: $e');
    }
    return entries;
  }

  /// Ensures each log entry stays on a single line and won't corrupt terminals.
  static String _sanitizeSingleLine(String input) {
    var s = input;
    // Normalize newline controls early.
    s = s.replaceAll('\r\n', '\n');

    // Strip ANSI escape sequences.
    s = s.replaceAll(_ansiOsc, '');
    s = s.replaceAll(_ansiCsi, '');
    s = s.replaceAll(_ansiSingle, '');

    // Preserve the original content while keeping one-line logs.
    s = s.replaceAll('\r', r'\r');
    s = s.replaceAll('\n', r'\n');

    // Remove other control characters (keep tabs, since they are useful in logs).
    s = s.replaceAll(_controlChars, '');
    return s;
  }
}
