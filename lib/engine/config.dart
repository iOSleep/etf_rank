/// Global configuration — direct port of Python's `class g`.
class Config {
  // ── ETF Pool ──
  /// Small pool (7, original "Seven Stars" core)
  static const List<String> etfPoolSmall = [
    "518880.XSHG", // 黄金ETF
    "159985.XSHE", // 豆粕ETF
    "501018.XSHG", // 南方原油
    "161226.XSHE", // 白银LOF
    "513100.XSHG", // 纳指ETF
    "159915.XSHE", // 创业板ETF
    "511220.XSHG", // 城投债ETF
  ];

  /// Full ETF pool (40 symbols)
  static const List<String> etfPool = [
    // Commodities
    "518880.XSHG", "159980.XSHE", "159985.XSHE", "501018.XSHG",
    "161226.XSHE", "159981.XSHE",
    // International
    "513100.XSHG", "159509.XSHE", "513290.XSHG", "513500.XSHG",
    "159529.XSHE", "513400.XSHG", "513520.XSHG", "513030.XSHG",
    "513080.XSHG", "513310.XSHG", "513730.XSHG",
    // Hong Kong
    "159792.XSHE", "513130.XSHG", "513050.XSHG", "159920.XSHE",
    "513690.XSHG",
    // Indices
    "510300.XSHG", "510500.XSHG", "510050.XSHG", "510210.XSHG",
    "159915.XSHE", "588080.XSHG", "512100.XSHG", "563360.XSHG",
    "563300.XSHG",
    // Styles
    "512890.XSHG", "159967.XSHE", "512040.XSHG", "159201.XSHE",
    // Bonds
    "511380.XSHG", "511010.XSHG", "511220.XSHG",
  ];

  static final Set<String> etfPoolSmallSet = etfPoolSmall.toSet();

  // ── Core Parameters ──
  static const int lookbackDays = 25;
  static const int holdingsNum = 1;
  static const String defensiveEtf = "511880.XSHG";
  static const int minMoney = 5000;

  // ── Profit Protection ──
  static const bool enableProfitProtection = true;
  static const int profitProtectionLookback = 1;
  static const double profitProtectionThreshold = 0.05;

  // ── Score Range ──
  static const double loss = 0.97;
  static const double minScoreThreshold = 0;
  static const double maxScoreThreshold = 100.0;

  // ── Volume Filter ──
  static const bool enableVolumeCheck = true;
  static const int volumeLookback = 5;
  static const double volumeThreshold = 2.0;
  static const double volumeReturnLimit = 1.0;

  // ── Short-term Momentum Filter ──
  static const bool useShortMomentumFilter = true;
  static const int shortLookbackDays = 10;
  static const double shortMomentumThreshold = 0.0;

  // ── Premium Rate Filter ──
  static const bool enablePremiumFilter = true;
  static const double premiumThreshold = 0.20;
  static const int premiumLookbackDays = 1;

  /// Strip exchange suffix: "518880.XSHG" → "518880"
  static String cleanCode(String code) {
    return code
        .replaceAll('.XSHG', '')
        .replaceAll('.XSHE', '')
        .replaceAll('.BJ', '');
  }

  /// Check if an ETF is in the small (core) pool
  static bool isSmall(String etf) => etfPoolSmallSet.contains(etf);
}
