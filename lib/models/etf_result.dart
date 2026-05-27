class EtfResult {
  final String etf;
  final String name;
  final double? score;
  final double? annual;
  final double? r2;
  final double? shortAnnual;
  final double? premium;
  final double? changePct;
  final List<dynamic>? klinesData;
  final String? filterReason;

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

  factory EtfResult.fromJson(Map<String, dynamic> json) => EtfResult(
    etf: json['etf'] as String,
    name: json['name'] as String,
    score: (json['score'] as num?)?.toDouble(),
    annual: (json['annual'] as num?)?.toDouble(),
    r2: (json['r2'] as num?)?.toDouble(),
    shortAnnual: (json['shortAnnual'] as num?)?.toDouble(),
    premium: (json['premium'] as num?)?.toDouble(),
    changePct: (json['changePct'] as num?)?.toDouble(),
    filterReason: json['filterReason'] as String?,
  );

  bool get passed => filterReason == null && score != null;

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
    'filterReason': filterReason,
  };
}

class RankingState {
  final List<EtfResult> results;
  final List<EtfResult> allItems;
  final List<EtfResult> targets;
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

  factory RankingState.fromJson(Map<String, dynamic> json) => RankingState(
    results: (json['results'] as List<dynamic>?)?.map((e) => EtfResult.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    allItems: (json['allItems'] as List<dynamic>?)?.map((e) => EtfResult.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    targets: (json['targets'] as List<dynamic>?)?.map((e) => EtfResult.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    lastUpdate: json['lastUpdate'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'results': results.map((e) => e.toJson()).toList(),
    'allItems': allItems.map((e) => e.toJson()).toList(),
    'targets': targets.map((e) => e.toJson()).toList(),
    'lastUpdate': lastUpdate,
  };

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
