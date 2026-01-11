import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static LogService? _instance;
  static LogService get instance => _instance ??= LogService._();

  LogService._();

  File? _logFile;
  IOSink? _sink;
  static const int _maxLogSize = 5 * 1024 * 1024; // 5MB

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

  void log(String level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$level] [$tag] $message\n';
    debugPrint(line.trim());
    _sink?.write(line);
  }

  void info(String tag, String message) => log('INFO', tag, message);
  void warn(String tag, String message) => log('WARN', tag, message);
  void error(String tag, String message) => log('ERROR', tag, message);

  Future<void> flush() async => await _sink?.flush();

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
