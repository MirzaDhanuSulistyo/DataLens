class CounterSample {
  const CounterSample({
    required this.rxBytes,
    required this.txBytes,
    required this.monotonicMillis,
    required this.bootId,
  });
  final int rxBytes;
  final int txBytes;
  final int monotonicMillis;
  final String bootId;
}

class UsageDelta {
  const UsageDelta({
    required this.rxBytes,
    required this.txBytes,
    required this.elapsedMillis,
  });
  final int rxBytes;
  final int txBytes;
  final int elapsedMillis;
}

UsageDelta? calculateDelta(CounterSample previous, CounterSample current) {
  if (previous.bootId != current.bootId ||
      current.monotonicMillis <= previous.monotonicMillis ||
      current.rxBytes < previous.rxBytes ||
      current.txBytes < previous.txBytes) {
    return null;
  }
  return UsageDelta(
    rxBytes: current.rxBytes - previous.rxBytes,
    txBytes: current.txBytes - previous.txBytes,
    elapsedMillis: current.monotonicMillis - previous.monotonicMillis,
  );
}
