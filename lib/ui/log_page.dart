import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// Show all logs except per-symbol scoring results and conclusions.
bool _shouldShow(LogEntry e) {
  if (e.level == LogLevel.warning || e.level == LogLevel.success) {
    if (e.message.contains('得分')) return false;
    if (e.level == LogLevel.warning && e.message.contains('数据不足')) return false;
  }
  return true;
}

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final allLogs = log.logs;
        final logs = allLogs.where(_shouldShow).toList();

        if (logs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: Color(0xFF16A34A)),
                SizedBox(height: 12),
                Text('暂无日志', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text('日志 ${logs.length} 条', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => log.clear(),
                    child: const Text('清空', style: TextStyle(fontSize: 12, color: Colors.blue)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[logs.length - 1 - index];
                  final time = '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';

                  Color? bgColor;
                  if (entry.level == LogLevel.error) { bgColor = Colors.red.shade50; }
                  else if (entry.level == LogLevel.warning) { bgColor = Colors.orange.shade50; }

                  return Container(
                    color: bgColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.levelIcon, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.message,
                            style: TextStyle(
                              fontSize: 12,
                              color: entry.level == LogLevel.error ? Colors.red : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
