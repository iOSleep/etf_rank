import '../models/etf_result.dart';
import 'config.dart';
import 'momentum.dart';
import 'filters.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';

class RankingEngine {
  final CacheService cache;

  RankingEngine({required this.cache});

  Future<List<EtfResult>> run({
    void Function(String status)? onStatus,
  }) async {
    final allItems = <EtfResult>[];
    const codes = Config.etfPool;

    onStatus?.call('正在加载K线数据...');
    log.cache('开始加载 ${codes.length} 只ETF的K线数据...');

    final klineMap = await cache.loadAll(
      codes,
      onProgress: (done, total) {
        onStatus?.call('加载K线 $done/$total...');
      },
    );

    final loadedCount = klineMap.values.where((k) => k.isNotEmpty).length;
    log.cache('K线加载完成: $loadedCount/${codes.length} 只有数据');

    onStatus?.call('正在获取实时行情...');
    log.api('请求腾讯实时行情...');
    final quotes = await ApiService.fetchRealTimeQuotes(codes);
    log.api('行情返回: ${quotes.length} 条');

    onStatus?.call('正在计算动量得分...');
    log.compute('开始计算 ${codes.length} 只ETF的动量得分...');

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    int passed = 0, filtered = 0;
    for (final etf in codes) {
      final clean = Config.cleanCode(etf);
      final klines = klineMap[etf] ?? [];
      final quote = quotes[clean];

      final name = quote?['name'] as String? ?? '未知';

      if (klines.length < Config.lookbackDays) {
        final reason = '⚠️ 数据不足(需${Config.lookbackDays}天, 仅${klines.length}天)';
        log.warn('$etf $name: $reason');
        allItems.add(EtfResult(etf: etf, name: name, klinesData: klines, filterReason: reason));
        filtered++;
        continue;
      }

      final priceSeries = klines.map((k) => k.close).toList();
      final currentPrice = quote?['price'] as double? ?? priceSeries.last;
      final lastClose = quote?['last_close'] as double? ?? 0;
      final changePct = lastClose > 0 ? (currentPrice - lastClose) / lastClose : null;

      final lastKlineDate = klines.last.date;
      if (lastKlineDate.year == todayDate.year &&
          lastKlineDate.month == todayDate.month &&
          lastKlineDate.day == todayDate.day) {
        priceSeries[priceSeries.length - 1] = currentPrice;
      } else {
        priceSeries.add(currentPrice);
      }

      final metrics = MomentumCalculator.compute(
        priceSeries,
        lookbackDays: Config.lookbackDays,
        shortLookbackDays: Config.shortLookbackDays,
      );
      final score = metrics.score;
      final annual = metrics.annual;
      final r2 = metrics.r2;
      final shortAnnual = metrics.shortAnnual;

      Map<String, dynamic>? navData;
      if (quote != null && quote.containsKey('unit_nav')) {
        navData = quote;
      }

      final pipeline = FilterPipeline(
        klines: klines,
        currentPrice: currentPrice,
        navData: navData,
        priceSeries: priceSeries,
        etf: etf,
        name: name,
      );

      final filterReason = pipeline.run(
        score: score,
        annual: annual,
        shortAnnual: shortAnnual,
      );

      if (filterReason != null) {
        log.warn('$etf $name: $filterReason (得分:${score.toStringAsFixed(4)})');
        allItems.add(EtfResult(
          etf: etf, name: name, score: score, annual: annual,
          r2: r2, shortAnnual: shortAnnual,
          premium: navData?['premium_rate'] as double?,
          changePct: changePct, klinesData: klines, filterReason: filterReason,
        ));
        filtered++;
      } else if (score <= Config.minScoreThreshold) {
        final reason = '📉 非上涨趋势: 得分${score.toStringAsFixed(4)} ≤ ${Config.minScoreThreshold}';
        log.warn('$etf $name: $reason');
        allItems.add(EtfResult(
          etf: etf, name: name, score: score, annual: annual,
          r2: r2, shortAnnual: shortAnnual,
          premium: navData?['premium_rate'] as double?, changePct: changePct, klinesData: klines, filterReason: reason,
        ));
        filtered++;
      } else if (score >= Config.maxScoreThreshold) {
        final reason = '🔥 强势: 得分${score.toStringAsFixed(4)} ≥ ${Config.maxScoreThreshold}';
        log.warn('$etf $name: $reason');
        allItems.add(EtfResult(
          etf: etf, name: name, score: score, annual: annual,
          r2: r2, shortAnnual: shortAnnual,
          premium: navData?['premium_rate'] as double?, changePct: changePct, klinesData: klines, filterReason: reason,
        ));
        filtered++;
      } else {
        log.success('$etf $name: 得分${score.toStringAsFixed(4)} 年化${(annual*100).toStringAsFixed(2)}% ✅');
        allItems.add(EtfResult(
          etf: etf, name: name, score: score, annual: annual,
          r2: r2, shortAnnual: shortAnnual,
          premium: navData?['premium_rate'] as double?,
          changePct: changePct, klinesData: klines, filterReason: null,
        ));
        passed++;
      }
    }

    log.info('计算完成: 通过 $passed 只, 过滤 $filtered 只');
    return allItems;
  }

  static RankingState buildState(List<EtfResult> allItems) {
    final passed = allItems
        .where((r) => r.passed)
        .toList()
      ..sort((a, b) => (b.score ?? -999).compareTo(a.score ?? -999));

    final targets = passed.take(Config.holdingsNum).toList();
    if (targets.isEmpty) {
      targets.add(const EtfResult(
        etf: Config.defensiveEtf, name: '银华日利',
        score: 0, annual: 0, r2: 0, shortAnnual: 0, filterReason: null,
      ));
    } else {
      log.success('🎯 今日推荐: ${targets.first.name} (${Config.cleanCode(targets.first.etf)})');
    }

    return RankingState(
      results: passed, allItems: allItems, targets: targets,
      loading: false, lastUpdate: _nowStr(), error: null,
    );
  }

  static String _nowStr() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '${now.year}-$m-$d $h:$min';
  }
}
