import 'dart:async';

import 'package:flutter/services.dart';

class CapabilityStatus {
  const CapabilityStatus({
    required this.platform,
    required this.usageAccess,
    required this.notifications,
    required this.monitoring,
    this.latestSampleAt,
    this.latestQuality,
    this.overlayPermission = false,
    this.overlayEnabled = false,
  });

  const CapabilityStatus.unsupported()
    : platform = 'unsupported',
      usageAccess = false,
      notifications = false,
      monitoring = false,
      latestSampleAt = null,
      latestQuality = null,
      overlayPermission = false,
      overlayEnabled = false;

  final String platform;
  final bool usageAccess;
  final bool notifications;
  final bool monitoring;
  final DateTime? latestSampleAt;
  final String? latestQuality;
  final bool overlayPermission;
  final bool overlayEnabled;

  factory CapabilityStatus.fromMap(Map<Object?, Object?> map) =>
      CapabilityStatus(
        platform: map['platform'] as String? ?? 'unsupported',
        usageAccess: map['usageAccess'] as bool? ?? false,
        notifications: map['notifications'] as bool? ?? false,
        monitoring: map['monitoring'] as bool? ?? false,
        latestSampleAt: switch (map['latestSampleAt']) {
          final num value => DateTime.fromMillisecondsSinceEpoch(value.toInt()),
          _ => null,
        },
        latestQuality: map['latestQuality'] as String?,
        overlayPermission: map['overlayPermission'] as bool? ?? false,
        overlayEnabled: map['overlayEnabled'] as bool? ?? false,
      );
}

class UsageTotal {
  const UsageTotal({this.rxBytes = 0, this.txBytes = 0});
  final int rxBytes;
  final int txBytes;
  int get totalBytes => rxBytes + txBytes;

  factory UsageTotal.fromMap(Map<Object?, Object?> map) => UsageTotal(
    rxBytes: (map['rxBytes'] as num?)?.toInt() ?? 0,
    txBytes: (map['txBytes'] as num?)?.toInt() ?? 0,
  );
}

class LiveCounters {
  const LiveCounters({
    required this.rxBytes,
    required this.txBytes,
    required this.monotonicMillis,
    required this.networkType,
  });
  final int rxBytes;
  final int txBytes;
  final int monotonicMillis;
  final String networkType;

  factory LiveCounters.fromMap(Map<Object?, Object?> map) => LiveCounters(
    rxBytes: (map['rxBytes'] as num?)?.toInt() ?? 0,
    txBytes: (map['txBytes'] as num?)?.toInt() ?? 0,
    monotonicMillis: (map['monotonicMillis'] as num?)?.toInt() ?? 0,
    networkType: map['networkType'] as String? ?? 'unknown',
  );
}

class AppUsageRecord {
  const AppUsageRecord({
    required this.id,
    required this.label,
    required this.rxBytes,
    required this.txBytes,
    required this.foregroundState,
    this.packageName,
    this.baselineSampleCount = 0,
    this.baselineBytes,
    this.excludedFromAlerts = false,
  });
  final int id;
  final String label;
  final String? packageName;
  final int rxBytes;
  final int txBytes;
  final String foregroundState;
  final int baselineSampleCount;
  final int? baselineBytes;
  final bool excludedFromAlerts;
  int get totalBytes => rxBytes + txBytes;
  bool get baselineMature => baselineSampleCount >= 7;

  factory AppUsageRecord.fromMap(Map<Object?, Object?> map) => AppUsageRecord(
    id: (map['id'] as num).toInt(),
    label: map['label'] as String,
    packageName: map['packageName'] as String?,
    rxBytes: (map['rxBytes'] as num).toInt(),
    txBytes: (map['txBytes'] as num).toInt(),
    foregroundState: map['foregroundState'] as String? ?? 'unknown',
    baselineSampleCount: (map['baselineSampleCount'] as num?)?.toInt() ?? 0,
    baselineBytes: (map['baselineBytes'] as num?)?.toInt(),
    excludedFromAlerts: map['excludedFromAlerts'] as bool? ?? false,
  );
}

class DeviceGuidance {
  const DeviceGuidance({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.title,
    required this.steps,
    required this.optimizationExempt,
  });

  const DeviceGuidance.unsupported()
    : manufacturer = 'Unknown',
      model = 'Unknown',
      androidVersion = '',
      title = 'Device guidance unavailable',
      steps = const [],
      optimizationExempt = false;

  final String manufacturer;
  final String model;
  final String androidVersion;
  final String title;
  final List<String> steps;
  final bool optimizationExempt;

  factory DeviceGuidance.fromMap(Map<Object?, Object?> map) => DeviceGuidance(
    manufacturer: map['manufacturer'] as String? ?? 'Unknown',
    model: map['model'] as String? ?? 'Unknown',
    androidVersion: map['androidVersion'] as String? ?? '',
    title: map['title'] as String? ?? 'Background setup',
    steps: (map['steps'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList(),
    optimizationExempt: map['optimizationExempt'] as bool? ?? false,
  );
}

class DailyUsageRecord {
  const DailyUsageRecord({required this.date, required this.total});
  final DateTime date;
  final UsageTotal total;

  factory DailyUsageRecord.fromMap(Map<Object?, Object?> map) =>
      DailyUsageRecord(
        date: DateTime.parse(map['date'] as String),
        total: UsageTotal.fromMap(map),
      );
}

class HourlyUsageRecord {
  const HourlyUsageRecord({required this.hour, required this.total});
  final DateTime hour;
  final UsageTotal total;

  factory HourlyUsageRecord.fromMap(Map<Object?, Object?> map) =>
      HourlyUsageRecord(
        hour: DateTime.parse(map['hour'] as String),
        total: UsageTotal.fromMap(map),
      );
}

class HotspotUsage {
  const HotspotUsage({
    this.state = 'unknown',
    this.stateQuality = 'unavailable',
    this.usageAvailable = false,
    this.today = const UsageTotal(),
    this.month = const UsageTotal(),
    this.session = const UsageTotal(),
    this.sessionStartedAt,
    this.lastUpdatedAt,
  });

  final String state;
  final String stateQuality;
  final bool usageAvailable;
  final UsageTotal today;
  final UsageTotal month;
  final UsageTotal session;
  final DateTime? sessionStartedAt;
  final DateTime? lastUpdatedAt;

  bool get active => state == 'active';
  bool get stateAvailable => state != 'unknown';

  factory HotspotUsage.fromMap(Map<Object?, Object?> map) => HotspotUsage(
    state: map['state'] as String? ?? 'unknown',
    stateQuality: map['stateQuality'] as String? ?? 'unavailable',
    usageAvailable: map['usageAvailable'] as bool? ?? false,
    today: UsageTotal.fromMap(map),
    month: UsageTotal(
      rxBytes: (map['monthRxBytes'] as num?)?.toInt() ?? 0,
      txBytes: (map['monthTxBytes'] as num?)?.toInt() ?? 0,
    ),
    session: UsageTotal(
      rxBytes: (map['sessionRxBytes'] as num?)?.toInt() ?? 0,
      txBytes: (map['sessionTxBytes'] as num?)?.toInt() ?? 0,
    ),
    sessionStartedAt: switch (map['sessionStartedAt']) {
      final num value => DateTime.fromMillisecondsSinceEpoch(value.toInt()),
      _ => null,
    },
    lastUpdatedAt: switch (map['lastUpdatedAt']) {
      final num value => DateTime.fromMillisecondsSinceEpoch(value.toInt()),
      _ => null,
    },
  );
}

class DataPlan {
  const DataPlan({
    required this.capBytes,
    required this.cycleDay,
    this.enabled = true,
  });
  final int capBytes;
  final int cycleDay;
  final bool enabled;

  factory DataPlan.fromMap(Map<Object?, Object?> map) => DataPlan(
    capBytes: (map['capBytes'] as num).toInt(),
    cycleDay: (map['cycleDay'] as num).toInt(),
    enabled: map['enabled'] as bool? ?? true,
  );
}

class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.type,
    required this.actualBytes,
    required this.state,
    required this.createdAt,
    this.appLabel,
    this.baselineBytes,
    this.ratio,
    this.networkType,
    this.foregroundState,
  });
  final int id;
  final String type;
  final int actualBytes;
  final String state;
  final DateTime createdAt;
  final String? appLabel;
  final int? baselineBytes;
  final double? ratio;
  final String? networkType;
  final String? foregroundState;

  factory AlertRecord.fromMap(Map<Object?, Object?> map) => AlertRecord(
    id: (map['id'] as num).toInt(),
    type: map['type'] as String,
    actualBytes: (map['actualBytes'] as num).toInt(),
    state: map['state'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num).toInt(),
    ),
    appLabel: map['appLabel'] as String?,
    baselineBytes: (map['baselineBytes'] as num?)?.toInt(),
    ratio: (map['ratio'] as num?)?.toDouble(),
    networkType: map['networkType'] as String?,
    foregroundState: map['foregroundState'] as String?,
  );
}

class WidgetPreferences {
  const WidgetPreferences({this.content = 'today', this.refreshMinutes = 30});

  final String content;
  final int refreshMinutes;

  WidgetPreferences copyWith({String? content, int? refreshMinutes}) =>
      WidgetPreferences(
        content: content ?? this.content,
        refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      );

  factory WidgetPreferences.fromMap(Map<Object?, Object?> map) =>
      WidgetPreferences(
        content: map['content'] as String? ?? 'today',
        refreshMinutes: (map['refreshMinutes'] as num?)?.toInt() ?? 30,
      );
}

class AlertPreferences {
  const AlertPreferences({
    this.sensitivity = 'medium',
    this.anomalyAlerts = true,
    this.newAppAlerts = true,
    this.backgroundAlerts = true,
  });

  final String sensitivity;
  final bool anomalyAlerts;
  final bool newAppAlerts;
  final bool backgroundAlerts;

  AlertPreferences copyWith({
    String? sensitivity,
    bool? anomalyAlerts,
    bool? newAppAlerts,
    bool? backgroundAlerts,
  }) => AlertPreferences(
    sensitivity: sensitivity ?? this.sensitivity,
    anomalyAlerts: anomalyAlerts ?? this.anomalyAlerts,
    newAppAlerts: newAppAlerts ?? this.newAppAlerts,
    backgroundAlerts: backgroundAlerts ?? this.backgroundAlerts,
  );

  factory AlertPreferences.fromMap(Map<Object?, Object?> map) =>
      AlertPreferences(
        sensitivity: map['sensitivity'] as String? ?? 'medium',
        anomalyAlerts: map['anomalyAlerts'] as bool? ?? true,
        newAppAlerts: map['newAppAlerts'] as bool? ?? true,
        backgroundAlerts: map['backgroundAlerts'] as bool? ?? true,
      );
}

abstract interface class UsageGateway {
  Stream<String> get destinationChanges;
  Future<String?> initialDestination();
  Future<CapabilityStatus> status();
  Future<void> openUsageAccessSettings();
  Future<void> openOverlaySettings();
  Future<bool> setOverlayEnabled(bool enabled);
  Future<bool> requestNotificationPermission();
  Future<void> startMonitoring();
  Future<void> stopMonitoring();
  Future<LiveCounters?> liveCounters();
  Future<void> sampleNow();
  Future<int> reconcileNow();
  Future<UsageTotal> summary(
    DateTime start,
    DateTime end, {
    String network = 'all',
  });
  Future<List<AppUsageRecord>> apps(
    DateTime start,
    DateTime end, {
    String network = 'all',
  });
  Future<List<DailyUsageRecord>> daily(
    DateTime start,
    DateTime end, {
    String network = 'all',
  });
  Future<List<HourlyUsageRecord>> hourly(
    DateTime start,
    DateTime end, {
    String network = 'all',
  });
  Future<HotspotUsage> hotspotUsage(
    DateTime start,
    DateTime end, {
    String network = 'all',
  });
  Future<DataPlan?> getPlan();
  Future<void> savePlan(DataPlan plan);
  Future<List<AlertRecord>> alerts();
  Future<AlertPreferences> getAlertPreferences();
  Future<void> saveAlertPreferences(AlertPreferences preferences);
  Future<WidgetPreferences> getWidgetPreferences();
  Future<void> saveWidgetPreferences(WidgetPreferences preferences);
  Future<int> getRetentionDays();
  Future<void> saveRetentionDays(int days);
  Future<void> setAppExcluded(int appId, bool excluded);
  Future<DeviceGuidance> getDeviceGuidance();
  Future<void> openBatterySettings();
  Future<bool> exportCsv();
  Future<bool> createBackup();
  Future<bool> restoreBackup();
  Future<void> deleteAllData();
}

class MethodChannelUsageGateway implements UsageGateway {
  MethodChannelUsageGateway() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'destinationChanged' && call.arguments is String) {
        _destinationController.add(call.arguments! as String);
      }
    });
  }

  static const _channel = MethodChannel('io.andura.datalens/usage');
  final _destinationController = StreamController<String>.broadcast();

  @override
  Stream<String> get destinationChanges => _destinationController.stream;

  @override
  Future<String?> initialDestination() =>
      _safe(() => _channel.invokeMethod<String>('getInitialDestination'), null);

  Future<T> _safe<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  @override
  Future<CapabilityStatus> status() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
    return CapabilityStatus.fromMap(value ?? const {});
  }, const CapabilityStatus.unsupported());

  @override
  Future<void> openUsageAccessSettings() =>
      _safe(() => _channel.invokeMethod<void>('openUsageAccessSettings'), null);

  @override
  Future<void> openOverlaySettings() =>
      _safe(() => _channel.invokeMethod<void>('openOverlaySettings'), null);

  @override
  Future<bool> setOverlayEnabled(bool enabled) => _safe(
    () async =>
        await _channel.invokeMethod<bool>('setOverlayEnabled', enabled) ??
        false,
    false,
  );

  @override
  Future<bool> requestNotificationPermission() => _safe(
    () async =>
        await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false,
    false,
  );

  @override
  Future<void> startMonitoring() =>
      _safe(() => _channel.invokeMethod<void>('startMonitoring'), null);

  @override
  Future<void> stopMonitoring() =>
      _safe(() => _channel.invokeMethod<void>('stopMonitoring'), null);

  @override
  Future<LiveCounters?> liveCounters() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'liveCounters',
    );
    return value == null ? null : LiveCounters.fromMap(value);
  }, null);

  @override
  Future<void> sampleNow() =>
      _safe(() => _channel.invokeMethod<void>('sampleNow'), null);

  @override
  Future<int> reconcileNow() => _safe(
    () async => await _channel.invokeMethod<int>('reconcileNow') ?? 0,
    0,
  );

  Map<String, Object> _range(DateTime start, DateTime end, String network) => {
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'network': network,
  };

  @override
  Future<UsageTotal> summary(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getSummary',
      _range(start, end, network),
    );
    return UsageTotal.fromMap(value ?? const {});
  }, const UsageTotal());

  @override
  Future<List<AppUsageRecord>> apps(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) => _safe(() async {
    final values = await _channel.invokeListMethod<Object?>(
      'getApps',
      _range(start, end, network),
    );
    return (values ?? const [])
        .map((value) => AppUsageRecord.fromMap(value! as Map<Object?, Object?>))
        .toList();
  }, const []);

  @override
  Future<List<DailyUsageRecord>> daily(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) => _safe(() async {
    final values = await _channel.invokeListMethod<Object?>(
      'getDailyUsage',
      _range(start, end, network),
    );
    return (values ?? const [])
        .map(
          (value) => DailyUsageRecord.fromMap(value! as Map<Object?, Object?>),
        )
        .toList();
  }, const []);

  @override
  Future<List<HourlyUsageRecord>> hourly(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) => _safe(() async {
    final values = await _channel.invokeListMethod<Object?>(
      'getHourlyUsage',
      _range(start, end, network),
    );
    return (values ?? const [])
        .map(
          (value) => HourlyUsageRecord.fromMap(value! as Map<Object?, Object?>),
        )
        .toList();
  }, const []);

  @override
  Future<HotspotUsage> hotspotUsage(
    DateTime start,
    DateTime end, {
    String network = 'all',
  }) => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getHotspotUsage',
      _range(start, end, network),
    );
    return HotspotUsage.fromMap(value ?? const {});
  }, const HotspotUsage());

  @override
  Future<DataPlan?> getPlan() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>('getPlan');
    return value == null ? null : DataPlan.fromMap(value);
  }, null);

  @override
  Future<void> savePlan(DataPlan plan) => _safe(
    () => _channel.invokeMethod<void>('savePlan', {
      'capBytes': plan.capBytes,
      'cycleDay': plan.cycleDay,
      'enabled': plan.enabled,
    }),
    null,
  );

  @override
  Future<List<AlertRecord>> alerts() => _safe(() async {
    final values = await _channel.invokeListMethod<Object?>('getAlerts');
    return (values ?? const [])
        .map((value) => AlertRecord.fromMap(value! as Map<Object?, Object?>))
        .toList();
  }, const []);

  @override
  Future<AlertPreferences> getAlertPreferences() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getAlertPreferences',
    );
    return AlertPreferences.fromMap(value ?? const {});
  }, const AlertPreferences());

  @override
  Future<void> saveAlertPreferences(AlertPreferences preferences) => _safe(
    () => _channel.invokeMethod<void>('saveAlertPreferences', {
      'sensitivity': preferences.sensitivity,
      'anomalyAlerts': preferences.anomalyAlerts,
      'newAppAlerts': preferences.newAppAlerts,
      'backgroundAlerts': preferences.backgroundAlerts,
    }),
    null,
  );

  @override
  Future<WidgetPreferences> getWidgetPreferences() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getWidgetPreferences',
    );
    return WidgetPreferences.fromMap(value ?? const {});
  }, const WidgetPreferences());

  @override
  Future<void> saveWidgetPreferences(WidgetPreferences preferences) => _safe(
    () => _channel.invokeMethod<void>('saveWidgetPreferences', {
      'content': preferences.content,
      'refreshMinutes': preferences.refreshMinutes,
    }),
    null,
  );

  @override
  Future<int> getRetentionDays() => _safe(
    () async => await _channel.invokeMethod<int>('getRetentionDays') ?? 365,
    365,
  );

  @override
  Future<void> saveRetentionDays(int days) =>
      _safe(() => _channel.invokeMethod<void>('saveRetentionDays', days), null);

  @override
  Future<void> setAppExcluded(int appId, bool excluded) => _safe(
    () => _channel.invokeMethod<void>('setAppExcluded', {
      'appId': appId,
      'excluded': excluded,
    }),
    null,
  );

  @override
  Future<DeviceGuidance> getDeviceGuidance() => _safe(() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getDeviceGuidance',
    );
    return DeviceGuidance.fromMap(value ?? const {});
  }, const DeviceGuidance.unsupported());

  @override
  Future<void> openBatterySettings() =>
      _safe(() => _channel.invokeMethod<void>('openBatterySettings'), null);

  Future<bool> _documentOperation(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> exportCsv() => _documentOperation('exportCsv');

  @override
  Future<bool> createBackup() => _documentOperation('createBackup');

  @override
  Future<bool> restoreBackup() => _documentOperation('restoreBackup');

  @override
  Future<void> deleteAllData() =>
      _safe(() => _channel.invokeMethod<void>('deleteAllData'), null);
}
