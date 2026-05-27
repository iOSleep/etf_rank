import 'package:flutter/material.dart';
import '../../models/etf_result.dart';
import '../../engine/config.dart';

/// Yellow banner showing today's recommended ETF (top target).
class SignalBanner extends StatelessWidget {
  final List<EtfResult> targets;
  const SignalBanner({super.key, required this.targets});

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) return const SizedBox.shrink();

    final t = targets.first;
    final displayCode = Config.cleanCode(t.etf);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '🎯 今日推荐：${t.name} ($displayCode)',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
