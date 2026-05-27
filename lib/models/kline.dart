/// Single daily K-line row.
class KlineRow {
  final DateTime date;
  final double open;
  final double close;
  final double high;
  final double low;
  final double volume;
  final double amount;

  const KlineRow({
    required this.date,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  factory KlineRow.fromJson(Map<String, dynamic> json) {
    return KlineRow(
      date: DateTime.parse(json['date'] as String),
      open: (json['open'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
      amount: (json['amount'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String().split('T').first,
        'open': open,
        'close': close,
        'high': high,
        'low': low,
        'volume': volume,
        'amount': amount,
      };
}
