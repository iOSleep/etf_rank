/// Result for a single ETF after momentum calculation and filtering.
class EtfResult {
  final String etf;    // e.g. "518880.XSHG"
  final String name;
  final double? score;      // annualized_return * r2
  final double? annual;     // annualized return from weighted regression
  final double? r2;         // R-squared
  final double? shortAnnual; // short-term annualized return
  final double? premium;    // premium rate
  final double? changePct;  // real-time change % (e.g. 0.05 = 5%)
  final List<dynamic>? klinesData; // cached K-line rows for chart
  final String? filterReason; // null means passed all filters

  const EtfResult({
    required this.etf,
    required this.name,
    this.score,
    this.annual,
    this.r2,
    this.shortAnnual,
    this.premium,
    this.changePct,
    this.klinesData,
    this.filterReason,
  });

  bool get passed => filterReason == null && score != null;

  /// Extract short filter tag for UI display.
  String get filterTag {
    if (filterReason == null) return '';
    final r = filterReason!;
    if (r.contains('溢价率')) return '溢价率';
    if (r.contains('盈利保护')) return '盈利保护';
    if (r.contains('成交量')) return '成交量';
    if (r.contains('短期动量')) return '短期动量';
    if (r.contains('跌幅')) return '跌幅';
    if (r.contains('数据不足')) return '数据不足';
    if (r.contains('得分')) return '得分';
    return '过滤';
  }

  Map<String, dynamic> toJson() => {
        'etf': etf,
        'name': name,
        'score': score,
        'annual': annual,
        'r2': r2,
        'shortAnnual': shortAnnual,
        'premium': premium,
        'changePct': changePct,
        'klinesData': klinesData?.map((k) => (k as dynamic).toJson()).toList(),
      };
}

/// Overall ranking state for the UI.
class RankingState {
  final List<EtfResult> results;   // passed, sorted by score desc
  final List<EtfResult> allItems;  // all (passed + filtered)
  final List<EtfResult> targets;   // selected holdings (top N)
  final bool loading;
  final String? lastUpdate;
  final String? error;

  const RankingState({
    this.results = const [],
    this.allItems = const [],
    this.targets = const [],
    this.loading = false,
    this.lastUpdate,
    this.error,
  });

  List<EtfResult> get passed => results;
  List<EtfResult> get failed => allItems.where((r) => !r.passed).toList();

  int get totalCount => allItems.length;
  int get passedCount => results.length;
  int get failedCount => totalCount - passedCount;

  RankingState copyWith({
    List<EtfResult>? results,
    List<EtfResult>? allItems,
    List<EtfResult>? targets,
    bool? loading,
    String? lastUpdate,
    String? error,
  }) {
    return RankingState(
      results: results ?? this.results,
      allItems: allItems ?? this.allItems,
      targets: targets ?? this.targets,
      loading: loading ?? this.loading,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error ?? this.error,
    );
  }
}
