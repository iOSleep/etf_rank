import 'package:flutter/material.dart';
import '../../models/etf_result.dart';
import '../../engine/config.dart';

class RankCard extends StatelessWidget {
  final EtfResult result;
  final int index;
  final bool isPassed;

  const RankCard({
    super.key,
    required this.result,
    required this.index,
    required this.isPassed,
  });

  String _pct(double? v) {
    if (v == null) return '-';
    final sign = v >= 0 ? '+' : '';
    return '$sign${(v * 100).toStringAsFixed(2)}%';
  }

  String _rankIcon() {
    if (!isPassed) return '⏭';
    if (index == 1) return '🥇';
    if (index == 2) return '🥈';
    if (index == 3) return '🥉';
    return '#$index';
  }

  @override
  Widget build(BuildContext context) {
    final displayCode = Config.cleanCode(result.etf);
    final isSmall = Config.isSmall(result.etf);
    final borderColor =
        isPassed ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusColor =
        isPassed ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusBg =
        isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final statusText = isPassed
        ? '得分 ${result.score?.toStringAsFixed(4) ?? "-"}'
        : result.filterTag;

    final annVal = result.annual ?? 0;
    final annColor =
        annVal > 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    // 实时涨跌幅
    final change = result.changePct;
    final changeColor = (change ?? 0) >= 0
        ? const Color(0xFFDC2626) // A股红涨
        : const Color(0xFF16A34A); // 绿跌

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: rank + name + change% + status
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    _rankIcon(),
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSmall
                                ? const Color(0xFFDC2626)
                                : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        displayCode,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // 涨跌幅
                if (change != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: change >= 0
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _pct(change),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: changeColor,
                      ),
                    ),
                  ),
                // 状态标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Bottom row: metrics
            Row(
              children: [
                if (isPassed && result.annual != null) ...[
                  Text('年化 ',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    _pct(result.annual),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: annColor),
                  ),
                  const SizedBox(width: 10),
                  Text('R² ',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    result.r2?.toStringAsFixed(4) ?? '-',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ],
                if (!isPassed) ...[
                  if (result.score != null) ...[
                    Text('得分 ${result.score!.toStringAsFixed(4)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      result.filterReason ?? '',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
