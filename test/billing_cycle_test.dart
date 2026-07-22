import 'package:datalens/features/plans/domain/billing_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('billingCycleFor', () {
    test('resolves day 31 to the final day of short months', () {
      final cycle = billingCycleFor(DateTime(2024, 2, 29, 12), 31);
      expect(cycle.start, DateTime(2024, 2, 29));
      expect(cycle.end, DateTime(2024, 3, 31));
    });

    test('uses previous month when current boundary is ahead', () {
      final cycle = billingCycleFor(DateTime(2025, 3, 15), 20);
      expect(cycle.start, DateTime(2025, 2, 20));
      expect(cycle.end, DateTime(2025, 3, 20));
    });

    test('rejects invalid cycle days', () {
      expect(() => billingCycleFor(DateTime(2025), 0), throwsArgumentError);
      expect(() => billingCycleFor(DateTime(2025), 32), throwsArgumentError);
    });
  });

  test('plan thresholds classify 80 and 100 percent', () {
    expect(planThreshold(usedBytes: 79, capBytes: 100), PlanThreshold.none);
    expect(
      planThreshold(usedBytes: 80, capBytes: 100),
      PlanThreshold.eightyPercent,
    );
    expect(planThreshold(usedBytes: 100, capBytes: 100), PlanThreshold.full);
  });
}
