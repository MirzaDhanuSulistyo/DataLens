import 'package:flutter/services.dart';

class CapabilityStatus {
  const CapabilityStatus({
    required this.platform,
    required this.usageAccess,
    required this.notifications,
    required this.monitoring,
    this.latestSampleAt,
    this.latestQuality,
  });

  const CapabilityStatus.unsupported()
    : platform = 'unsupported',
      usageAccess = false,
      notifications = false,
      monitoring = false,
      latestSampleAt = null,
      latestQuality = null;

  final String platform;
  final bool usageAccess;
  final bool notifications;
  final bool monitoring;
  final DateTime? latestSampleAt;
  final String? latestQuality;

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
  });
  final int id;
  final String label;
  final String? packageName;
  final int rxBytes;
  final int txBytes;
  final String foregroundState;
  int get totalBytes => rxBytes + txBytes;

  factory AppUsageRecord.fromMap(Map<Object?, Object?> map) => AppUsageRecord(
    id: (map['id'] as num).toInt(),
    label: map['label'] as String,
    packageName: map['packageName'] as String?,
    rxBytes: (map['rxBytes'] as num).toInt(),
    txBytes: (map['txBytes'] as num).toInt(),
    foregroundState: map['foregroundState'] as String? ?? 'unknown',
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
  });
  final int id;
  final String type;
  final int actualBytes;
  final String state;
  final DateTime createdAt;

  factory AlertRecord.fromMap(Map<Object?, Object?> map) => AlertRecord(
    id: (map['id'] as num).toInt(),
    type: map['type'] as String,
    actualBytes: (map['actualBytes'] as num).toInt(),
    state: map['state'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num).toInt(),
    ),
  );
}

abstract interface class UsageGateway {
  Future<CapabilityStatus> status();
  Future<void> openUsageAccessSettings();
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
  Future<DataPlan?> getPlan();
  Future<void> savePlan(DataPlan plan);
  Future<List<AlertRecord>> alerts();
  Future<void> deleteAllData();
}

class MethodChannelUsageGateway implements UsageGateway {
  static const _channel = MethodChannel('io.andura.datalens/usage');

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
  Future<void> deleteAllData() =>
      _safe(() => _channel.invokeMethod<void>('deleteAllData'), null);
}
