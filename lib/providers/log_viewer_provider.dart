import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/log_entry.dart';
import '../data/services/log_service.dart';

class LogFilter {
  final Set<String> levels;
  final String? tag;
  final String keyword;
  final DateTime? startDate;
  final DateTime? endDate;

  const LogFilter({
    this.levels = const {'INFO', 'WARN', 'ERROR'},
    this.tag,
    this.keyword = '',
    this.startDate,
    this.endDate,
  });

  LogFilter copyWith({
    Set<String>? levels,
    String? Function()? tag,
    String? keyword,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
  }) {
    return LogFilter(
      levels: levels ?? this.levels,
      tag: tag != null ? tag() : this.tag,
      keyword: keyword ?? this.keyword,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
    );
  }
}

class LogViewerState {
  final List<LogEntry> allLogs;
  final LogFilter filter;
  final bool isLoading;
  final String? error;

  const LogViewerState({
    this.allLogs = const [],
    this.filter = const LogFilter(),
    this.isLoading = false,
    this.error,
  });

  List<LogEntry> get filteredLogs {
    return allLogs.where((log) {
      if (!filter.levels.contains(log.level)) return false;
      if (filter.tag != null && log.tag != filter.tag) return false;
      if (filter.keyword.isNotEmpty &&
          !log.message.toLowerCase().contains(filter.keyword.toLowerCase())) {
        return false;
      }
      if (filter.startDate != null && log.timestamp.isBefore(filter.startDate!)) {
        return false;
      }
      if (filter.endDate != null) {
        final endOfDay = DateTime(filter.endDate!.year, filter.endDate!.month, filter.endDate!.day, 23, 59, 59);
        if (log.timestamp.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();
  }

  Set<String> get allTags => allLogs.map((e) => e.tag).toSet();

  LogViewerState copyWith({
    List<LogEntry>? allLogs,
    LogFilter? filter,
    bool? isLoading,
    String? Function()? error,
  }) {
    return LogViewerState(
      allLogs: allLogs ?? this.allLogs,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }
}

class LogViewerNotifier extends Notifier<LogViewerState> {
  @override
  LogViewerState build() => const LogViewerState();

  Future<void> loadLogs() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final logs = await LogService.instance.readLogs();
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = state.copyWith(allLogs: logs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: () => e.toString());
    }
  }

  void setLevels(Set<String> levels) {
    state = state.copyWith(filter: state.filter.copyWith(levels: levels));
  }

  void toggleLevel(String level) {
    final levels = Set<String>.from(state.filter.levels);
    if (levels.contains(level)) {
      levels.remove(level);
    } else {
      levels.add(level);
    }
    state = state.copyWith(filter: state.filter.copyWith(levels: levels));
  }

  void setTag(String? tag) {
    state = state.copyWith(filter: state.filter.copyWith(tag: () => tag));
  }

  void setKeyword(String keyword) {
    state = state.copyWith(filter: state.filter.copyWith(keyword: keyword));
  }

  void setDateRange(DateTime? start, DateTime? end) {
    state = state.copyWith(
      filter: state.filter.copyWith(startDate: () => start, endDate: () => end),
    );
  }

  void clearFilter() {
    state = state.copyWith(filter: const LogFilter());
  }
}

final logViewerProvider = NotifierProvider<LogViewerNotifier, LogViewerState>(
  LogViewerNotifier.new,
);
