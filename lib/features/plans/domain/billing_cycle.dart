class BillingCycle {
  const BillingCycle({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  int get daysRemaining {
    final now = DateTime.now();
    return end
        .difference(DateTime(now.year, now.month, now.day))
        .inDays
        .clamp(0, 366);
  }
}

BillingCycle billingCycleFor(DateTime instant, int cycleDay) {
  if (cycleDay < 1 || cycleDay > 31) {
    throw ArgumentError.value(cycleDay, 'cycleDay', 'must be between 1 and 31');
  }
  DateTime boundary(int year, int month) {
    final firstNext = month == 12
        ? DateTime(year + 1, 1)
        : DateTime(year, month + 1);
    final lastDay = firstNext.subtract(const Duration(days: 1)).day;
    return DateTime(year, month, cycleDay.clamp(1, lastDay));
  }

  final local = instant.toLocal();
  var start = boundary(local.year, local.month);
  if (local.isBefore(start)) {
    final previous = DateTime(local.year, local.month - 1);
    start = boundary(previous.year, previous.month);
  }
  final next = DateTime(start.year, start.month + 1);
  return BillingCycle(start: start, end: boundary(next.year, next.month));
}

enum PlanThreshold { none, eightyPercent, full }

PlanThreshold planThreshold({required int usedBytes, required int capBytes}) {
  if (capBytes <= 0 || usedBytes < 0) return PlanThreshold.none;
  if (usedBytes >= capBytes) return PlanThreshold.full;
  if (usedBytes >= capBytes * .8) return PlanThreshold.eightyPercent;
  return PlanThreshold.none;
}
