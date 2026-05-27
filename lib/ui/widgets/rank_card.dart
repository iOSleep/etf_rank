import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/kline.dart';
import '../../models/etf_result.dart';
import '../../engine/config.dart';

class RankCard extends StatefulWidget {
  final EtfResult result;
  final int index;
  final bool isPassed;

  const RankCard({
    super.key,
    required this.result,
    required this.index,
    required this.isPassed,
  });

  @override
  State<RankCard> createState() => _RankCardState();
}

class _RankCardState extends State<RankCard> {
  bool _expanded = false;

  String _pct(double? v) {
    if (v == null) return '-';
    final sign = v >= 0 ? '+' : '';
    return '$sign${(v * 100).toStringAsFixed(2)}%';
  }

  String _rankIcon() {
    if (!widget.isPassed) return '⏭';
    if (widget.index == 1) return '🥇';
    if (widget.index == 2) return '🥈';
    if (widget.index == 3) return '🥉';
    return '#${widget.index}';
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final displayCode = Config.cleanCode(result.etf);
    final isSmall = Config.isSmall(result.etf);
    final borderColor = widget.isPassed
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final statusColor = widget.isPassed
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final statusBg = widget.isPassed
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEE2E2);
    final statusText = widget.isPassed
        ? '得分 ${result.score?.toStringAsFixed(4) ?? "-"}'
        : result.filterTag;

    final annVal = result.annual ?? 0;
    final annColor =
        annVal > 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    final change = result.changePct;
    final changeColor = (change ?? 0) >= 0
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
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
              // Top row
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
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (change != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
              // Bottom row: metrics + expand hint
              Row(
                children: [
                  if (widget.isPassed && result.annual != null) ...[
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
                  if (!widget.isPassed) ...[
                    if (result.score != null) ...[
                      Text('得分 ${result.score!.toStringAsFixed(4)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
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
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
              // Expand: K-line chart
              if (_expanded) _buildChart(result),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(EtfResult result) {
    final raw = result.klinesData;
    if (raw == null || raw.length < 5) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('K线数据不足', style: TextStyle(fontSize: 11, color: Colors.grey)),
      );
    }

    // Extract close prices (last 30)
    final closes = <double>[];
    final dates = <String>[];
    for (final k in raw) {
      if (k is KlineRow) {
        closes.add(k.close);
        dates.add('${k.date.month}/${k.date.day}');
      }
    }
    if (closes.length < 5) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('K线数据不足', style: TextStyle(fontSize: 11, color: Colors.grey)),
      );
    }

    final showCloses = closes.length > 30 ? closes.sublist(closes.length - 30) : closes;
    final minY = showCloses.reduce((a, b) => a < b ? a : b);
    final maxY = showCloses.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.05;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('近${30 > showCloses.length ? showCloses.length : 30}日收盘价',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 4),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((maxY + pad) - (minY - pad)) / 4,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: minY - pad,
                maxY: maxY + pad,
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      showCloses.length,
                      (i) => FlSpot(i.toDouble(), showCloses[i]),
                    ),
                    isCurved: true,
                    color: const Color(0xFF2563EB),
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
