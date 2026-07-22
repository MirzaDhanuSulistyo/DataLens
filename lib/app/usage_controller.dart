import 'dart:async';

import 'package:datalens/core/platform/usage_gateway.dart';
import 'package:datalens/features/plans/domain/billing_cycle.dart';
import 'package:flutter/foundation.dart';

class UsageController extends ChangeNotifier {
  UsageController(this.gateway);

  final UsageGateway gateway;
  CapabilityStatus capabilities = const CapabilityStatus.unsupported();
  UsageTotal today = const UsageTotal();
  UsageTotal cycleUsage = const UsageTotal();
  List<AppUsageRecord> apps = const [];
  List<DailyUsageRecord> dailyUsage = const [];
  List<HourlyUsageRecord> hourlyUsage = const [];
  List<AlertRecord> alerts = const [];
  HotspotUsage hotspot = const HotspotUsage();
  DataPlan? plan;
  AlertPreferences alertPreferences = const AlertPreferences();
  WidgetPreferences widgetPreferences = const WidgetPreferences();
  int retentionDays = 365;
  int selectedDestination = 0;
  String network = 'all';
  bool loading = true;
  String? error;
  double? downloadBitsPerSecond;
  double? uploadBitsPerSecond;
  String liveNetwork = 'unknown';

  Timer? _liveTimer;
  StreamSubscription<String>? _destinationSubscription;
  LiveCounters? _previousCounters;
  bool _liveRequestPending = false;
  final List<double> _downWindow = [];
  final List<double> _upWindow = [];

  Future<void> initialize() async {
    _destinationSubscription = gateway.destinationChanges.listen(navigateTo);
    navigateTo(await gateway.initialDestination());
    capabilities = await gateway.status();
    await refreshData();
    if (capabilities.monitoring) _startLiveUpdates();
  }

  void navigateTo(String? destination) {
    final index = switch (destination) {
      'apps' => 1,
      'history' => 2,
      'alerts' => 3,
      'settings' => 4,
      _ => 0,
    };
    if (selectedDestination == index) return;
    selectedDestination = index;
    notifyListeners();
  }

  void selectDestination(int index) {
    if (selectedDestination == index) return;
    selectedDestination = index;
    notifyListeners();
  }

  Future<void> refreshData() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      capabilities = await gateway.status();
      plan = await gateway.getPlan();
      alertPreferences = await gateway.getAlertPreferences();
      widgetPreferences = await gateway.getWidgetPreferences();
      retentionDays = await gateway.getRetentionDays();
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final currentHour = DateTime(now.year, now.month, now.day, now.hour);
      final cycle = billingCycleFor(now, plan?.cycleDay ?? 1);
      final values = await Future.wait<Object>([
        gateway.summary(startToday, now, network: network),
        gateway.summary(cycle.start, now, network: 'mobile'),
        gateway.apps(startToday, now, network: network),
        gateway.daily(
          startToday.subtract(const Duration(days: 6)),
          now,
          network: network,
        ),
        gateway.hourly(
          currentHour.subtract(const Duration(hours: 23)),
          now,
          network: network,
        ),
        gateway.alerts(),
        gateway.hotspotUsage(
          startToday,
          now,
          network: network == 'hotspot' ? 'all' : network,
        ),
      ]);
      hotspot = values[6] as HotspotUsage;
      today = network == 'hotspot' ? hotspot.today : values[0] as UsageTotal;
      cycleUsage = values[1] as UsageTotal;
      apps = values[2] as List<AppUsageRecord>;
      dailyUsage = values[3] as List<DailyUsageRecord>;
      hourlyUsage = values[4] as List<HourlyUsageRecord>;
      alerts = values[5] as List<AlertRecord>;
    } catch (_) {
      error = 'Usage data could not be loaded. Try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setNetwork(String value) async {
    network = switch (value) {
      'Mobile' => 'mobile',
      'Wi-Fi' => 'wifi',
      'Hotspot' => 'hotspot',
      _ => 'all',
    };
    await refreshData();
  }

  Future<void> openUsageSettings() async {
    await gateway.openUsageAccessSettings();
  }

  Future<void> startMonitoring() async {
    await gateway.requestNotificationPermission();
    await gateway.startMonitoring();
    await gateway.sampleNow();
    capabilities = await gateway.status();
    _startLiveUpdates();
    await refreshData();
  }

  Future<void> stopMonitoring() async {
    await gateway.stopMonitoring();
    _liveTimer?.cancel();
    _previousCounters = null;
    downloadBitsPerSecond = null;
    uploadBitsPerSecond = null;
    capabilities = await gateway.status();
    notifyListeners();
  }

  Future<void> reconcile() async {
    loading = true;
    notifyListeners();
    await gateway.reconcileNow();
    await refreshData();
  }

  Future<void> updatePlan(DataPlan value) async {
    await gateway.savePlan(value);
    plan = value;
    await refreshData();
  }

  Future<void> updateAlertPreferences(AlertPreferences value) async {
    alertPreferences = value;
    notifyListeners();
    await gateway.saveAlertPreferences(value);
  }

  Future<void> updateWidgetPreferences(WidgetPreferences value) async {
    widgetPreferences = value;
    notifyListeners();
    await gateway.saveWidgetPreferences(value);
  }

  Future<void> updateRetentionDays(int value) async {
    retentionDays = value;
    notifyListeners();
    await gateway.saveRetentionDays(value);
    await refreshData();
  }

  Future<void> openOverlaySettings() => gateway.openOverlaySettings();

  Future<void> setOverlayEnabled(bool enabled) async {
    final applied = await gateway.setOverlayEnabled(enabled);
    capabilities = await gateway.status();
    notifyListeners();
    if (enabled && !applied) await gateway.openOverlaySettings();
  }

  Future<void> deleteAllData() async {
    await gateway.stopMonitoring();
    await gateway.deleteAllData();
    _liveTimer?.cancel();
    _previousCounters = null;
    capabilities = await gateway.status();
    await refreshData();
  }

  void _startLiveUpdates() {
    _liveTimer?.cancel();
    _readLiveCounters();
    _liveTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _readLiveCounters(),
    );
  }

  Future<void> _readLiveCounters() async {
    if (_liveRequestPending) return;
    _liveRequestPending = true;
    try {
      final current = await gateway.liveCounters();
      final previous = _previousCounters;
      _previousCounters = current;
      if (current == null) return;
      liveNetwork = current.networkType;
      if (previous == null ||
          current.monotonicMillis <= previous.monotonicMillis) {
        notifyListeners();
        return;
      }
      final elapsed =
          (current.monotonicMillis - previous.monotonicMillis) / 1000;
      final rx = current.rxBytes - previous.rxBytes;
      final tx = current.txBytes - previous.txBytes;
      if (rx < 0 || tx < 0) {
        downloadBitsPerSecond = null;
        uploadBitsPerSecond = null;
      } else {
        _push(_downWindow, rx * 8 / elapsed);
        _push(_upWindow, tx * 8 / elapsed);
        downloadBitsPerSecond = _average(_downWindow);
        uploadBitsPerSecond = _average(_upWindow);
      }
      notifyListeners();
    } finally {
      _liveRequestPending = false;
    }
  }

  void _push(List<double> values, double value) {
    values.add(value);
    if (values.length > 4) values.removeAt(0);
  }

  double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  @override
  void dispose() {
    _liveTimer?.cancel();
    _destinationSubscription?.cancel();
    super.dispose();
  }
}
