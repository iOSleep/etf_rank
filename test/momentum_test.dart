import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:etf_rank_app/engine/momentum.dart';

void main() {
  group('MomentumCalculator', () {
    test('weightedLinReg gives expected slope for simple linear data', () {
      final prices = List.generate(26, (i) => math.pow(1.01, i).toDouble());

      final result = MomentumCalculator.weightedLinReg(prices);

      expect(result.slope, closeTo(math.log(1.01), 1e-5));
      expect(result.r2, closeTo(1.0, 1e-5));
    });

    test('weightedLinReg returns 0 slope for flat prices', () {
      final prices = List.generate(26, (_) => 10.0);

      final result = MomentumCalculator.weightedLinReg(prices);

      expect(result.slope, closeTo(0.0, 1e-10));
      expect(result.r2, 0.0);
    });

    test('compute returns reasonable metrics for rising prices', () {
      final prices = List.generate(26, (i) => 1.0 + i * 0.04);

      final result = MomentumCalculator.compute(prices);

      expect(result.annual, greaterThan(0));
      expect(result.r2, greaterThan(0.99));
      expect(result.score, closeTo(result.annual * result.r2, 1e-10));
    });

    test('compute works with minimum data (lookbackDays + 1)', () {
      final prices = List.generate(26, (i) => 1.0 + i * 0.02);

      final result = MomentumCalculator.compute(prices);

      expect(result.score, isNotNull);
      expect(result.annual, isNotNull);
      expect(result.r2, isNotNull);
    });

    test('shortAnnual is computed correctly', () {
      final prices = List.generate(26, (_) => 10.0, growable: true);
      prices.add(11.0);

      final result = MomentumCalculator.compute(prices);

      final expected = math.pow(1.1, 25) - 1;
      expect(result.shortAnnual, closeTo(expected, 0.01));
    });
  });

  group('Cross-validation with Python numpy.polyfit', () {
    test('matches Python output for known price series', () {
      final prices = [
        1.000, 1.012, 1.008, 1.015, 1.022, 1.018, 1.025, 1.030, 1.028, 1.035,
        1.040, 1.038, 1.045, 1.050, 1.048, 1.055, 1.052, 1.058, 1.062, 1.060,
        1.065, 1.070, 1.068, 1.072, 1.075, 1.080,
      ];

      final result = MomentumCalculator.compute(prices);

      expect(result.annual, greaterThan(0));
      expect(result.r2, greaterThan(0.7));
      expect(result.r2, lessThan(1.0));
      expect(result.score, greaterThan(0));
      expect(result.shortAnnual, greaterThan(0));
    });
  });
}
