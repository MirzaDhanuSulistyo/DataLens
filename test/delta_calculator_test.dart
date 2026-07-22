import 'package:datalens/features/tracking/domain/delta_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const previous = CounterSample(
    rxBytes: 100,
    txBytes: 50,
    monotonicMillis: 1000,
    bootId: 'boot-a',
  );

  test('calculates positive deltas with monotonic elapsed time', () {
    const current = CounterSample(
      rxBytes: 160,
      txBytes: 80,
      monotonicMillis: 2500,
      bootId: 'boot-a',
    );
    final delta = calculateDelta(previous, current)!;
    expect(delta.rxBytes, 60);
    expect(delta.txBytes, 30);
    expect(delta.elapsedMillis, 1500);
  });

  test('rejects counter resets and reboot boundaries', () {
    const reset = CounterSample(
      rxBytes: 90,
      txBytes: 80,
      monotonicMillis: 2500,
      bootId: 'boot-a',
    );
    const reboot = CounterSample(
      rxBytes: 160,
      txBytes: 80,
      monotonicMillis: 2500,
      bootId: 'boot-b',
    );
    expect(calculateDelta(previous, reset), isNull);
    expect(calculateDelta(previous, reboot), isNull);
  });
}
