import 'dart:async';

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
  AlertPreferences alertPreferences = const AlertPreferences();
  WidgetPreferences widgetPreferences = const WidgetPreferences();
  int retentionDays = 365;
  DeviceGuidance deviceGuidance = const DeviceGuidance(
    manufacturer: 'Google',
    model: 'Pixel Test',
    androidVersion: '15',
    title: 'Pixel background setup',
    steps: ['Allow background battery use for reliable monitoring.'],
    optimizationExempt: false,
  );
  bool csvExported = false;
  bool backupCreated = false;
  bool backupRestored = false;
  String? initialDestinationValue;
  final destinationController = StreamController<String>.broadcast();

  @override
  Stream<String> get destinationChanges => destinationController.stream;

  @override
  Future<String?> initialDestination() async => initialDestinationValue;

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
  Future<List<HourlyUsageRecord>> hourly(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => [
    HourlyUsageRecord(
      hour: DateTime.now().subtract(const Duration(hours: 1)),
      total: network == 'hotspot' ? hotspot.today : total,
    ),
  ];

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
  Future<WidgetPreferences> getWidgetPreferences() async => widgetPreferences;

  @override
  Future<int> getRetentionDays() async => retentionDays;

  @override
  Future<DeviceGuidance> getDeviceGuidance() async => deviceGuidance;

  @override
  Future<HotspotUsage> hotspotUsage(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => hotspot;

  @override
  Future<AlertPreferences> getAlertPreferences() async => alertPreferences;

  @override
  Future<LiveCounters?> liveCounters() async => null;

  @override
  Future<void> openOverlaySettings() async {}

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<int> reconcileNow() async => 0;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> sampleNow() async {}

  @override
  Future<void> saveAlertPreferences(AlertPreferences preferences) async =>
      alertPreferences = preferences;

  @override
  Future<void> savePlan(DataPlan value) async => plan = value;

  @override
  Future<void> saveWidgetPreferences(WidgetPreferences preferences) async =>
      widgetPreferences = preferences;

  @override
  Future<void> saveRetentionDays(int days) async => retentionDays = days;

  @override
  Future<void> setAppExcluded(int appId, bool excluded) async {
    appRecords = [
      for (final app in appRecords)
        if (app.id == appId)
          AppUsageRecord(
            id: app.id,
            label: app.label,
            packageName: app.packageName,
            rxBytes: app.rxBytes,
            txBytes: app.txBytes,
            foregroundState: app.foregroundState,
            baselineSampleCount: app.baselineSampleCount,
            baselineBytes: app.baselineBytes,
            excludedFromAlerts: excluded,
          )
        else
          app,
    ];
  }

  @override
  Future<bool> exportCsv() async => csvExported = true;

  @override
  Future<bool> createBackup() async => backupCreated = true;

  @override
  Future<bool> restoreBackup() async => backupRestored = true;

  @override
  Future<bool> setOverlayEnabled(bool enabled) async => enabled;

  @override
  Future<void> startMonitoring() async {
    capabilityStatus = CapabilityStatus(
      platform: capabilityStatus.platform,
      usageAccess: capabilityStatus.usageAccess,
      notifications: true,
      monitoring: true,
      overlayPermission: capabilityStatus.overlayPermission,
      overlayEnabled: capabilityStatus.overlayEnabled,
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
      overlayPermission: capabilityStatus.overlayPermission,
      overlayEnabled: capabilityStatus.overlayEnabled,
    );
  }

  @override
  Future<UsageTotal> summary(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => network == 'hotspot' ? hotspot.today : total;
}
