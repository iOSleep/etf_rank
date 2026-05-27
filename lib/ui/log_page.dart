import 'package:flutter/material.dart';
import '../services/log_service.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final logs = log.logs;
        if (logs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.article_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('暂无日志，下拉刷新开始', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 顶部操作栏
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text('共 ${logs.length} 条', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => log.clear(),
                    child: const Text('清空', style: TextStyle(fontSize: 12, color: Colors.blue)),
                  ),
                ],
              ),
            ),
            // 日志列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[logs.length - 1 - index]; // 最新在上
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
