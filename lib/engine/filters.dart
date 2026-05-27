import 'dart:math' as math;
import '../models/kline.dart';
import 'config.dart';

/// Filter result returned by each filter check.
class FilterResult {
  final bool filtered;
  final String? reason;
  const FilterResult({required this.filtered, this.reason});
  static const pass = FilterResult(filtered: false);
  static FilterResult block(String reason) =>
      FilterResult(filtered: true, reason: reason);
}

/// Filter pipeline — 6 filters, same order as Python.
class FilterPipeline {
  final List<KlineRow> klines;
  final double currentPrice;
  final Map<String, dynamic>? navData; // from Tencent API
  final List<double> priceSeries;
  final String etf;
  final String name;

  FilterPipeline({
    required this.klines,
    required this.currentPrice,
    required this.navData,
    required this.priceSeries,
    required this.etf,
    required this.name,
  });

  /// Run all 6 filters in order.
  /// Returns null if all pass, or the filter reason string.
  String? run({
    required double score,
    required double annual,
    required double shortAnnual,
  }) {
    // Filter 1: Profit Protection
    final fp = _checkProfitProtection();
    if (fp.filtered) return fp.reason;

    // Filter 2: Premium Rate
    final fpr = _checkPremiumRate();
    if (fpr.filtered) return fpr.reason;

    // Filter 3: Volume
    final fv = _checkVolume(annual);
    if (fv.filtered) return fv.reason;

    // Filter 4: Short-term Momentum
    final fsm = _checkShortMomentum(shortAnnual);
    if (fsm.filtered) return fsm.reason;

    // Filter 5: Score range (handled by caller)
    // Filter 6: Recent 3-day drawdown
    final fd = _checkRecentDrawdown();
    if (fd.filtered) return fd.reason;

    return null; // all passed
  }

  /// Filter 1: Profit Protection
  /// Current price <= max_high * (1 - threshold) → filter
  FilterResult _checkProfitProtection() {
    if (!Config.enableProfitProtection) return FilterResult.pass;
    if (klines.length < Config.profitProtectionLookback) return FilterResult.pass;

    const lookback = Config.profitProtectionLookback;
    final relevant = klines.sublist(klines.length - lookback);
    final double maxHigh = relevant.map((k) => k.high).reduce(math.max);
    const double threshold = Config.profitProtectionThreshold;
    final double limit = maxHigh * (1 - threshold);

    if (currentPrice <= limit) {
      return FilterResult.block(
        '🛡️ 盈利保护: 当前${currentPrice.toStringAsFixed(4)} <= '
            '近$lookback日最高${maxHigh.toStringAsFixed(4)}×(1-${(threshold * 100).toInt()}%)=${limit.toStringAsFixed(4)}',
      );
    }
    return FilterResult.pass;
  }

  /// Filter 2: Premium Rate
  /// |premium| > 20% → filter
  FilterResult _checkPremiumRate() {
    if (!Config.enablePremiumFilter) return FilterResult.pass;
    if (navData == null) return FilterResult.pass;

    final premium = navData!['premium_rate'] as double?;
    if (premium == null) return FilterResult.pass;

    if (premium.abs() > Config.premiumThreshold) {
      final ref = navData!['iopv'] != null ? 'IOPV' : '单位净值';
      return FilterResult.block(
        '❌ 溢价率过滤: 溢价率${(premium * 100).toStringAsFixed(2)}% > '
            '阈值${(Config.premiumThreshold * 100).toInt()}% (基于$ref)',
      );
    }
    return FilterResult.pass;
  }

  /// Filter 3: Volume check
  /// volume_ratio > threshold AND annualized > volumeReturnLimit → filter
  FilterResult _checkVolume(double annual) {
    if (!Config.enableVolumeCheck) return FilterResult.pass;
    if (klines.length < Config.volumeLookback) return FilterResult.pass;

    const lookback = Config.volumeLookback;
    final relevant = klines.sublist(klines.length - lookback);
    final double avgVol =
        relevant.map((k) => k.volume).reduce((a, b) => a + b) / lookback;
    final double curVol = klines.last.volume;
    if (avgVol <= 0) return FilterResult.pass;

    final double ratio = curVol / avgVol;
    if (ratio > Config.volumeThreshold && annual > Config.volumeReturnLimit) {
      return FilterResult.block(
        '📊 成交量过滤: 当日量/5日均量=${ratio.toStringAsFixed(1)}倍'
            '(阈值${Config.volumeThreshold.toInt()}), '
            '年化${(annual * 100).toStringAsFixed(1)}% > ${(Config.volumeReturnLimit * 100).toInt()}%',
      );
    }
    return FilterResult.pass;
  }

  /// Filter 4: Short-term momentum
  /// shortAnnual < threshold → filter
  FilterResult _checkShortMomentum(double shortAnnual) {
    if (!Config.useShortMomentumFilter) return FilterResult.pass;
    if (shortAnnual < Config.shortMomentumThreshold) {
      return FilterResult.block(
        '⏳ 短期动量过滤: 近${Config.shortLookbackDays}日年化${(shortAnnual * 100).toStringAsFixed(2)}% < '
            '阈值${(Config.shortMomentumThreshold * 100).toInt()}%',
      );
    }
    return FilterResult.pass;
  }

  /// Filter 6: Recent 3-day drawdown
  /// Any single day return < loss (0.97 = -3%) → filter
  FilterResult _checkRecentDrawdown() {
    if (priceSeries.length < 4) return FilterResult.pass;

    final day1 =
        priceSeries[priceSeries.length - 1] / priceSeries[priceSeries.length - 2];
    final day2 =
        priceSeries[priceSeries.length - 2] / priceSeries[priceSeries.length - 3];
    final day3 =
        priceSeries[priceSeries.length - 3] / priceSeries[priceSeries.length - 4];
    final double minReturn = [day1, day2, day3].reduce(math.min);

    if (minReturn < Config.loss) {
      return FilterResult.block(
        '📉 跌幅过滤: 近3日最小单日收益${((minReturn - 1) * 100).toStringAsFixed(2)}% < '
            '阈值${((Config.loss - 1) * 100).toInt()}%',
      );
    }
    return FilterResult.pass;
  }
}
