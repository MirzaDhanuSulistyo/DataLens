import 'dart:async';
import 'package:flutter/material.dart';
import 'package:datalens/core/platform/usage_gateway.dart';
import 'package:datalens/main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DataLensApp(gateway: DemoUsageGateway()));
}

class DemoUsageGateway implements UsageGateway {
  DemoUsageGateway() {
    _initData();
  }

  CapabilityStatus _capabilityStatus = const CapabilityStatus(
    platform: 'web_simulator',
    usageAccess: true,
    notifications: true,
    monitoring: true,
    latestQuality: 'active',
  );

  DataPlan? _plan = const DataPlan(
    capBytes: 30 * 1000 * 1000 * 1000, // 30 GB
    cycleDay: 1,
  );

  UsageTotal _total = const UsageTotal(
    rxBytes: 12450000000, // ~12.45 GB
    txBytes: 1850000000,  // ~1.85 GB
  );

  late HotspotUsage _hotspot;
  late List<AppUsageRecord> _appRecords;
  late List<AlertRecord> _alertRecords;
  AlertPreferences _alertPreferences = const AlertPreferences();
  WidgetPreferences _widgetPreferences = const WidgetPreferences();
  int _retentionDays = 365;

  final DeviceGuidance _deviceGuidance = const DeviceGuidance(
    manufacturer: 'Pixel / Android',
    model: 'Interactive Web Simulator',
    androidVersion: '15',
    title: 'Simulator Active',
    steps: [
      'DataLens is running in interactive web simulation mode.',
      'All charts, plan alerts, and app toggles update in real time.',
    ],
    optimizationExempt: true,
  );

  String? _initialDestinationValue;
  final _destinationController = StreamController<String>.broadcast();

  void _initData() {
    final now = DateTime.now();

    _hotspot = HotspotUsage(
      state: 'active',
      stateQuality: 'system_callback',
      usageAvailable: true,
      today: const UsageTotal(rxBytes: 420000000, txBytes: 85000000),
      month: const UsageTotal(rxBytes: 2400000000, txBytes: 520000000),
      session: const UsageTotal(rxBytes: 150000000, txBytes: 32000000),
      sessionStartedAt: now.subtract(const Duration(minutes: 38)),
      lastUpdatedAt: now,
    );

    _appRecords = [
      const AppUsageRecord(
        id: 1,
        label: 'YouTube',
        packageName: 'com.google.android.youtube',
        rxBytes: 4120000000,
        txBytes: 210000000,
        foregroundState: 'foreground',
        baselineSampleCount: 14,
        baselineBytes: 2800000000,
      ),
      const AppUsageRecord(
        id: 2,
        label: 'Instagram',
        packageName: 'com.instagram.android',
        rxBytes: 2850000000,
        txBytes: 450000000,
        foregroundState: 'foreground',
        baselineSampleCount: 14,
        baselineBytes: 1900000000,
      ),
      const AppUsageRecord(
        id: 3,
        label: 'Chrome Browser',
        packageName: 'com.android.chrome',
        rxBytes: 1950000000,
        txBytes: 320000000,
        foregroundState: 'foreground',
        baselineSampleCount: 14,
        baselineBytes: 1200000000,
      ),
      const AppUsageRecord(
        id: 4,
        label: 'Spotify',
        packageName: 'com.spotify.music',
        rxBytes: 980000000,
        txBytes: 45000000,
        foregroundState: 'background',
        baselineSampleCount: 14,
        baselineBytes: 650000000,
      ),
      const AppUsageRecord(
        id: 5,
        label: 'WhatsApp',
        packageName: 'com.whatsapp',
        rxBytes: 840000000,
        txBytes: 390000000,
        foregroundState: 'foreground',
        baselineSampleCount: 14,
        baselineBytes: 700000000,
      ),
      const AppUsageRecord(
        id: 6,
        label: 'Netflix',
        packageName: 'com.netflix.mediaclient',
        rxBytes: 750000000,
        txBytes: 28000000,
        foregroundState: 'foreground',
        baselineSampleCount: 7,
        baselineBytes: 500000000,
      ),
      const AppUsageRecord(
        id: 7,
        label: 'Slack',
        packageName: 'com.Slack',
        rxBytes: 420000000,
        txBytes: 180000000,
        foregroundState: 'background',
        baselineSampleCount: 14,
        baselineBytes: 300000000,
      ),
      const AppUsageRecord(
        id: 8,
        label: 'Android OS System',
        packageName: 'android.system',
        rxBytes: 290000000,
        txBytes: 95000000,
        foregroundState: 'background',
        baselineSampleCount: 14,
        baselineBytes: 250000000,
      ),
    ];

    _alertRecords = [
      AlertRecord(
        id: 1,
        appLabel: 'Instagram',
        type: 'anomaly',
        actualBytes: 320000000,
        baselineBytes: 50000000,
        ratio: 6.4,
        networkType: 'mobile',
        foregroundState: 'background',
        state: 'unread',
        createdAt: now.subtract(const Duration(hours: 2, minutes: 15)),
      ),
      AlertRecord(
        id: 2,
        type: 'threshold',
        actualBytes: 15000000000,
        state: 'unread',
        createdAt: now.subtract(const Duration(hours: 8, minutes: 40)),
      ),
    ];
  }

  @override
  Stream<String> get destinationChanges => _destinationController.stream;

  @override
  Future<String?> initialDestination() async => _initialDestinationValue;

  @override
  Future<List<AlertRecord>> alerts() async => _alertRecords;

  @override
  Future<void> markAllAlertsRead() async {
    _alertRecords = [
      for (final alert in _alertRecords) alert.copyWith(state: 'read'),
    ];
  }

  @override
  Future<List<AppUsageRecord>> apps(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => network == 'hotspot' ? const [] : _appRecords;

  @override
  Future<List<DailyUsageRecord>> daily(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async {
    final now = DateTime.now();
    final days = <DailyUsageRecord>[];
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final multiplier = 0.6 + ((i * 7) % 11) * 0.08;
      final dayRx = (450000000 * multiplier).toInt();
      final dayTx = (65000000 * multiplier).toInt();
      days.add(
        DailyUsageRecord(
          date: date,
          total: UsageTotal(rxBytes: dayRx, txBytes: dayTx),
        ),
      );
    }
    return days;
  }

  @override
  Future<List<HourlyUsageRecord>> hourly(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async {
    final now = DateTime.now();
    final hours = <HourlyUsageRecord>[];
    for (int i = 23; i >= 0; i--) {
      final hour = now.subtract(Duration(hours: i));
      final hourVal = hour.hour;
      final activity = (hourVal >= 8 && hourVal <= 23)
          ? (0.4 + ((hourVal * 13) % 10) * 0.07)
          : 0.05;
      final hRx = (90000000 * activity).toInt();
      final hTx = (15000000 * activity).toInt();
      hours.add(
        HourlyUsageRecord(
          hour: hour,
          total: network == 'hotspot'
              ? UsageTotal(rxBytes: (hRx * 0.3).toInt(), txBytes: (hTx * 0.3).toInt())
              : UsageTotal(rxBytes: hRx, txBytes: hTx),
        ),
      );
    }
    return hours;
  }

  @override
  Future<void> deleteAllData() async {
    _total = const UsageTotal();
    _appRecords = const [];
    _plan = null;
    _alertRecords = const [];
  }

  @override
  Future<DataPlan?> getPlan() async => _plan;

  @override
  Future<WidgetPreferences> getWidgetPreferences() async => _widgetPreferences;

  @override
  Future<int> getRetentionDays() async => _retentionDays;

  @override
  Future<DeviceGuidance> getDeviceGuidance() async => _deviceGuidance;

  @override
  Future<HotspotUsage> hotspotUsage(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => _hotspot;

  @override
  Future<AlertPreferences> getAlertPreferences() async => _alertPreferences;

  @override
  Future<LiveCounters?> liveCounters() async => LiveCounters(
    rxBytes: 12450000000,
    txBytes: 1850000000,
    monotonicMillis: DateTime.now().millisecondsSinceEpoch,
    networkType: 'mobile',
  );

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
  Future<void> saveAlertPreferences(AlertPreferences preferences) async {
    _alertPreferences = preferences;
  }

  @override
  Future<void> savePlan(DataPlan value) async {
    _plan = value;
  }

  @override
  Future<void> saveWidgetPreferences(WidgetPreferences preferences) async {
    _widgetPreferences = preferences;
  }

  @override
  Future<void> saveRetentionDays(int days) async {
    _retentionDays = days;
  }

  @override
  Future<void> setAppExcluded(int appId, bool excluded) async {
    _appRecords = [
      for (final app in _appRecords)
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
  Future<bool> exportCsv() async => true;

  @override
  Future<bool> createBackup() async => true;

  @override
  Future<bool> restoreBackup() async => true;

  @override
  Future<bool> setOverlayEnabled(bool enabled) async => enabled;

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  Future<CapabilityStatus> status() async => _capabilityStatus;

  @override
  Future<UsageTotal> summary(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) async => _total;
}
