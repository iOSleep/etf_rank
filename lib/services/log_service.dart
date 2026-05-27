import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime time;
  final String message;
  final LogLevel level;

  const LogEntry({
    required this.time,
    required this.message,
    this.level = LogLevel.info,
  });

  String get levelIcon {
    switch (level) {
      case LogLevel.info: return 'ℹ️';
      case LogLevel.success: return '✅';
      case LogLevel.warning: return '⚠️';
      case LogLevel.error: return '❌';
      case LogLevel.api: return '🌐';
      case LogLevel.cache: return '📦';
      case LogLevel.compute: return '🔢';
    }
  }
}

enum LogLevel { info, success, warning, error, api, cache, compute }

class LogService extends ChangeNotifier {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;
  LogService._();

  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => List.unmodifiable(_logs);

  void _add(String message, LogLevel level) {
    final entry = LogEntry(time: DateTime.now(), message: message, level: level);
    _logs.add(entry);
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);

    // 同时输出到终端，方便调试
    final ts = '${entry.time.hour.toString().padLeft(2,'0')}:${entry.time.minute.toString().padLeft(2,'0')}:${entry.time.second.toString().padLeft(2,'0')}';
    debugPrint('[$ts] ${entry.levelIcon} $message');

    notifyListeners();
  }

  void info(String msg) => _add(msg, LogLevel.info);
  void success(String msg) => _add(msg, LogLevel.success);
  void warn(String msg) => _add(msg, LogLevel.warning);
  void error(String msg) => _add(msg, LogLevel.error);
  void api(String msg) => _add(msg, LogLevel.api);
  void cache(String msg) => _add(msg, LogLevel.cache);
  void compute(String msg) => _add(msg, LogLevel.compute);

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}

LogService get log => LogService.instance;
