import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/kline.dart';
import '../../models/etf_result.dart';
import '../../engine/config.dart';

class RankCard extends StatefulWidget {
  final EtfResult result;
  final int index;
  final bool isPassed;
  const RankCard({super.key, required this.result, required this.index, required this.isPassed});
  @override
  State<RankCard> createState() => _RankCardState();
}

class _RankCardState extends State<RankCard> {
  bool _expanded = false;

  String _pct(double? v) {
    if (v == null) return '-';
    return '${v >= 0 ? "+" : ""}${(v * 100).toStringAsFixed(2)}%';
  }
  String _rankIcon() {
    if (!widget.isPassed) return '\u23ED';
    if (widget.index == 1) return '\uD83E\uDD47';
    if (widget.index == 2) return '\uD83E\uDD48';
    if (widget.index == 3) return '\uD83E\uDD49';
    return '#${widget.index}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final code = Config.cleanCode(r.etf);
    final small = Config.isSmall(r.etf);
    const green = Color(0xFF16A34A);
    const red = Color(0xFFDC2626);
    final border = widget.isPassed ? green : red;
    final ann = r.annual ?? 0;
    final annC = ann > 0 ? green : red;
    final chg = r.changePct;
    final chgC = (chg ?? 0) >= 0 ? red : green;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: border, width: 3)),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1))]),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Top: rank + name/code + [score badge] ──
            Row(children: [
              SizedBox(width: 32, child: Text(_rankIcon(), style: const TextStyle(fontSize: 16), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              Expanded(child: Row(children: [
                Flexible(child: Text(r.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: small ? red : Colors.black87), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Text(code, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ])),
              // 右上角：始终显示得分
              if (r.score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text('得分 ${r.score!.toStringAsFixed(4)}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: widget.isPassed ? green : red)),
                ),
            ]),
            const SizedBox(height: 6),
            // ── Bottom ──
            Row(children: [
              if (widget.isPassed && r.annual != null) ...[
                const Text('年化 ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(_pct(r.annual), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: annC)),
                const SizedBox(width: 8),
                const Text('R\u00B2 ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(r.r2?.toStringAsFixed(4) ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                if (chg != null) ...[
                  const SizedBox(width: 8),
                  Text(_pct(chg), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: chgC)),
                ],
              ],
              if (!widget.isPassed && r.filterReason != null) ...[
                // 过滤标签小胶囊
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                  child: Text(r.filterTag, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                ),
                const SizedBox(width: 6),
                // 过滤原因占满右侧
                Expanded(
                  child: Text(r.filterReason!, style: const TextStyle(fontSize: 11, color: Color(0xFF999999)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
              if (widget.isPassed) const Spacer(),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey),
            ]),
            if (_expanded) _chart(r),
          ]))),
    );
  }

  Widget _chart(EtfResult r) {
    final raw = r.klinesData;
    if (raw == null || raw.length < 5) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('K线数据不足', style: TextStyle(fontSize: 11, color: Colors.grey)));
    final closes = <double>[];
    final dates = <String>[];
    for (final k in raw) {
      if (k is KlineRow) { closes.add(k.close); dates.add('${k.date.month}/${k.date.day}'); }
    }
    if (closes.length < 5) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('K线数据不足', style: TextStyle(fontSize: 11, color: Colors.grey)));
    final show = closes.length > 30 ? closes.sublist(closes.length - 30) : closes;
    final sd = dates.length > 30 ? dates.sublist(dates.length - 30) : dates;
    final min = show.reduce((a, b) => a < b ? a : b);
    final max = show.reduce((a, b) => a > b ? a : b);
    final pad = (max - min) * 0.08;
    final up = show.last >= show.first;
    final line = up ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    final fill = up ? const Color(0xFFDC2626).withValues(alpha: 0.06) : const Color(0xFF16A34A).withValues(alpha: 0.06);
    return Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('近${show.length}日收盘价', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
        const Spacer(),
        Text('${show.first.toStringAsFixed(3)} → ${show.last.toStringAsFixed(3)}', style: TextStyle(fontSize: 10, color: line, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 6),
      SizedBox(height: 140, child: LineChart(LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: ((max + pad) - (min - pad)) / 4,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade300, strokeWidth: 0.5)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36,
            getTitlesWidget: (v, _) => Padding(padding: const EdgeInsets.only(right: 4), child: Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 8, color: Color(0xFFAAAAAA)))))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20,
            interval: show.length > 15 ? (show.length / 4).ceilToDouble() : 1,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= sd.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 4), child: Text(sd[i], style: const TextStyle(fontSize: 8, color: Color(0xFFBBBBBB))));
            })),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false), minY: min - pad, maxY: max + pad,
        lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) => spots.map((s) {
          final i = s.x.toInt();
          final d = i >= 0 && i < sd.length ? sd[i] : '';
          return LineTooltipItem('$d\n${s.y.toStringAsFixed(3)}', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600));
        }).toList())),
        lineBarsData: [LineChartBarData(
          spots: List.generate(show.length, (i) => FlSpot(i.toDouble(), show[i])),
          isCurved: true, curveSmoothness: 0.3, color: line, barWidth: 2,
          dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: fill),
        )],
      ))),
    ]));
  }
}
