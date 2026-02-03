class LogEntry {
  final DateTime timestamp;
  final String level;
  final String tag;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  static LogEntry? parse(String line) {
    // Format: [timestamp] [level] [tag] message
    final regex = RegExp(r'^\[(.+?)\] \[(\w+)\] \[(.+?)\] (.*)$');
    final match = regex.firstMatch(line);
    if (match == null) return null;

    final timestamp = DateTime.tryParse(match.group(1)!);
    if (timestamp == null) return null;

    return LogEntry(
      timestamp: timestamp,
      level: match.group(2)!,
      tag: match.group(3)!,
      message: match.group(4)!,
    );
  }
}
