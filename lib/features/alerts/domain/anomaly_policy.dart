import 'dart:math' as math;

enum AlertSensitivity { off, low, medium, high }

class BaselineStats {
  const BaselineStats({
    required this.sampleCount,
    required this.centerBytes,
    required this.dispersionBytes,
  });

  final int sampleCount;
  final double centerBytes;
  final double dispersionBytes;
  bool get mature => sampleCount >= 7;
}

class AnomalyDecision {
  const AnomalyDecision({
    required this.triggered,
    required this.ratio,
    required this.minimumBytes,
  });

  final bool triggered;
  final double ratio;
  final int minimumBytes;
}

BaselineStats robustBaseline(Iterable<int> samples) {
  final sorted = samples.map((value) => math.max(0, value)).toList()..sort();
  if (sorted.isEmpty) {
    return const BaselineStats(
      sampleCount: 0,
      centerBytes: 0,
      dispersionBytes: 0,
    );
  }
  final center = _median(sorted.map((value) => value.toDouble()).toList());
  final deviations = sorted.map((value) => (value - center).abs()).toList()
    ..sort();
  return BaselineStats(
    sampleCount: sorted.length,
    centerBytes: center,
    dispersionBytes: _median(deviations),
  );
}

AnomalyDecision evaluateDailyAnomaly({
  required int actualBytes,
  required BaselineStats baseline,
  required AlertSensitivity sensitivity,
}) {
  final (
    requiredRatio,
    minimumBytes,
    dispersionMultiplier,
  ) = switch (sensitivity) {
    AlertSensitivity.off => (double.infinity, 1 << 62, 0.0),
    AlertSensitivity.low => (3.0, 250 * 1000 * 1000, 4.0),
    AlertSensitivity.medium => (2.5, 100 * 1000 * 1000, 3.0),
    AlertSensitivity.high => (2.0, 50 * 1000 * 1000, 2.0),
  };
  // A small floor prevents a near-zero learned median from producing a noisy
  // or infinite comparison while still allowing a genuinely large spike.
  final comparison = math.max(baseline.centerBytes, 1000 * 1000);
  final ratio = math.max(0, actualBytes) / comparison;
  final robustUpper =
      baseline.centerBytes +
      dispersionMultiplier * 1.4826 * baseline.dispersionBytes;
  return AnomalyDecision(
    triggered:
        baseline.mature &&
        actualBytes >= minimumBytes &&
        ratio >= requiredRatio &&
        actualBytes >= robustUpper,
    ratio: ratio,
    minimumBytes: minimumBytes,
  );
}

double _median(List<double> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
