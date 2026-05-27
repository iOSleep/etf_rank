import 'package:flutter/material.dart';
import '../../state/ranking_store.dart';

/// Top stats bar showing total / passed / filtered counts + last update time.
class StatsBar extends StatelessWidget {
  final RankingStore store;
  const StatsBar({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final state = store.state;
    final total = state.totalCount;
    final passed = state.passedCount;
    final failed = state.failedCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('共 $total 只', style: const TextStyle(fontSize: 12, color: Colors.black87)),
          const SizedBox(width: 16),
          Text(
            '✅ 通过 $passed',
            style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          Text(
            '⛔ 过滤 $failed',
            style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
          ),
          if (state.lastUpdate != null) ...[
            const SizedBox(width: 16),
            Text(
              '⏱ ${state.lastUpdate}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
