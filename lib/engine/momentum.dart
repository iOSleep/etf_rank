import 'dart:math' as math;

/// Weighted linear regression for momentum scoring.
///
/// Port of Python's numpy polyfit with weights: np.polyfit(x, y, 1, w=weights)
/// Uses analytic least-squares solution with centered data for numerical stability.
class MomentumCalculator {
  /// Compute weighted linear regression slope & intercept on log(prices).
  ///
  /// Returns a record (slope, intercept, r2).
  static ({double slope, double intercept, double r2}) weightedLinReg(
    List<double> prices, {
    double weightStart = 1.0,
    double weightEnd = 2.0,
  }) {
    final int n = prices.length;
    final List<double> y = prices.map((p) => math.log(p)).toList();
    final List<double> x = List.generate(n, (i) => i.toDouble());
    final List<double> w = List.generate(
      n,
      (i) => weightStart + (weightEnd - weightStart) * i / (n - 1),
    );

    // Weighted means
    double sumW = 0, sumWx = 0, sumWy = 0;
    for (int i = 0; i < n; i++) {
      sumW += w[i];
      sumWx += w[i] * x[i];
      sumWy += w[i] * y[i];
    }
    final double xBar = sumWx / sumW;
    final double yBar = sumWy / sumW;

    // Weighted covariance and variance (centered)
    double cov = 0, varX = 0;
    for (int i = 0; i < n; i++) {
      final double dx = x[i] - xBar;
      cov += w[i] * dx * (y[i] - yBar);
      varX += w[i] * dx * dx;
    }

    final double slope = varX != 0 ? cov / varX : 0;
    final double intercept = yBar - slope * xBar;

    // Weighted R²
    double ssRes = 0, ssTot = 0;
    for (int i = 0; i < n; i++) {
      final double pred = slope * x[i] + intercept;
      ssRes += w[i] * (y[i] - pred) * (y[i] - pred);
      ssTot += w[i] * (y[i] - yBar) * (y[i] - yBar);
    }
    final double r2 = ssTot != 0 ? 1 - ssRes / ssTot : 0;

    return (slope: slope, intercept: intercept, r2: r2);
  }

  /// Compute full momentum metrics for a price series.
  ///
  /// Uses the most recent [lookbackDays+1] data points for the regression.
  static ({
    double score,
    double annual,
    double r2,
    double shortAnnual,
  }) compute(
    List<double> prices, {
    int lookbackDays = 25,
    int shortLookbackDays = 10,
  }) {
    // Regression on lookbackDays + 1 points
    final int len = prices.length;
    final int n = math.min(lookbackDays + 1, len);
    final List<double> recent = prices.sublist(len - n);

    final reg = weightedLinReg(recent);
    final double slope = reg.slope;
    final double r2 = reg.r2;
    final double annual = math.exp(slope * 250) - 1;
    final double score = annual * r2;

    // Short-term annualized return
    double shortAnnual = 0;
    if (len >= shortLookbackDays + 1) {
      final double p0 = prices[len - shortLookbackDays - 1];
      final double p1 = prices.last;
      if (p0 > 0) {
        final double shortReturn = p1 / p0 - 1;
        shortAnnual = math.pow(1 + shortReturn, 250 / shortLookbackDays) - 1;
      }
    }

    return (score: score, annual: annual, r2: r2, shortAnnual: shortAnnual);
  }

  /// Annualized return from weighted regression (used for volume filter).
  static double annualizedReturn(List<double> prices, {int lookbackDays = 25}) {
    final int len = prices.length;
    final int n = math.min(lookbackDays + 1, len);
    final List<double> recent = prices.sublist(len - n);
    final reg = weightedLinReg(recent);
    return math.exp(reg.slope * 250) - 1;
  }
}
