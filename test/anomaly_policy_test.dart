import 'package:datalens/features/alerts/domain/anomaly_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('robust baseline uses median and median absolute deviation', () {
    final baseline = robustBaseline([10, 11, 9, 10, 12, 10, 1000]);

    expect(baseline.sampleCount, 7);
    expect(baseline.centerBytes, 10);
    expect(baseline.dispersionBytes, 1);
    expect(baseline.mature, isTrue);
  });

  test('baseline requires seven samples', () {
    final decision = evaluateDailyAnomaly(
      actualBytes: 500 * 1000 * 1000,
      baseline: robustBaseline(List.filled(6, 50 * 1000 * 1000)),
      sensitivity: AlertSensitivity.high,
    );

    expect(decision.triggered, isFalse);
  });

  test('medium sensitivity requires ratio and byte floor', () {
    final baseline = robustBaseline(List.filled(7, 40 * 1000 * 1000));

    expect(
      evaluateDailyAnomaly(
        actualBytes: 99 * 1000 * 1000,
        baseline: baseline,
        sensitivity: AlertSensitivity.medium,
      ).triggered,
      isFalse,
    );
    expect(
      evaluateDailyAnomaly(
        actualBytes: 110 * 1000 * 1000,
        baseline: baseline,
        sensitivity: AlertSensitivity.medium,
      ).triggered,
      isTrue,
    );
  });

  test('off sensitivity never triggers', () {
    final decision = evaluateDailyAnomaly(
      actualBytes: 1000 * 1000 * 1000,
      baseline: robustBaseline(List.filled(14, 1)),
      sensitivity: AlertSensitivity.off,
    );

    expect(decision.triggered, isFalse);
  });
}
