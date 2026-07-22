import 'package:datalens/core/platform/usage_gateway.dart';

class FakeUsageGateway implements UsageGateway {
  CapabilityStatus capabilityStatus = const CapabilityStatus(
    platform: 'android',
    usageAccess: true,
    notifications: true,
    monitoring: true,
  );
  DataPlan? plan = const DataPlan(
    capBytes: 30 * 1000 * 1000 * 1000,
    cycleDay: 1,
  );
  UsageTotal total = const UsageTotal(rxBytes: 900000000, txBytes: 380000000);
  HotspotUsage hotspot = HotspotUsage(
    state: 'active',
    stateQuality: 'system_callback',
    usageAvailable: true,
    today: const UsageTotal(rxBytes: 180000000, txBytes: 60000000),
    month: const UsageTotal(rxBytes: 900000000, txBytes: 200000000),
    session: const UsageTotal(rxBytes: 80000000, txBytes: 20000000),
    sessionStartedAt: DateTime.now().subtract(const Duration(minutes: 42)),
    lastUpdatedAt: DateTime.now(),
  );
  List<AppUsageRecord> appRecords = const [
    AppUsageRecord(
      id: 1,
      label: 'Browser',
      packageName: 'example.browser',
      rxBytes: 400000000,
      txBytes: 20000000,
      foregroundState: 'foreground',
    ),
  ];
  bool deleted = false;

  @override
  Future<List<AlertRecord>> alerts() async => const [];

  @override
  Future<List<AppUsageRecord>> apps(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => network == 'hotspot' ? const [] : appRecords;

  @override
  Future<List<DailyUsageRecord>> daily(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => [DailyUsageRecord(date: DateTime.now(), total: total)];

  @override
  Future<void> deleteAllData() async {
    deleted = true;
    total = const UsageTotal();
    appRecords = const [];
    plan = null;
  }

  @override
  Future<DataPlan?> getPlan() async => plan;

  @override
  Future<HotspotUsage> hotspotUsage(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => hotspot;

  @override
  Future<LiveCounters?> liveCounters() async => null;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<int> reconcileNow() async => 0;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> sampleNow() async {}

  @override
  Future<void> savePlan(DataPlan value) async => plan = value;

  @override
  Future<void> startMonitoring() async {
    capabilityStatus = CapabilityStatus(
      platform: capabilityStatus.platform,
      usageAccess: capabilityStatus.usageAccess,
      notifications: true,
      monitoring: true,
    );
  }

  @override
  Future<CapabilityStatus> status() async => capabilityStatus;

  @override
  Future<void> stopMonitoring() async {
    capabilityStatus = CapabilityStatus(
      platform: capabilityStatus.platform,
      usageAccess: capabilityStatus.usageAccess,
      notifications: capabilityStatus.notifications,
      monitoring: false,
    );
  }

  @override
  Future<UsageTotal> summary(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => network == 'hotspot' ? hotspot.today : total;
}
