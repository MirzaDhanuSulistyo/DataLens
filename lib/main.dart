import 'package:andura_ui/andura_ui.dart';
import 'package:datalens/app/usage_controller.dart';
import 'package:datalens/core/formatters/byte_formatter.dart';
import 'package:datalens/core/platform/usage_gateway.dart';
import 'package:datalens/features/plans/domain/billing_cycle.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DataLensApp());

class DataLensApp extends StatelessWidget {
  const DataLensApp({super.key, this.gateway});

  final UsageGateway? gateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DataLens',
      debugShowCheckedModeBanner: false,
      theme: AnduraTheme.light,
      darkTheme: AnduraTheme.dark,
      themeMode: ThemeMode.system,
      home: DataLensHome(gateway: gateway ?? MethodChannelUsageGateway()),
    );
  }
}

class DataLensHome extends StatefulWidget {
  const DataLensHome({required this.gateway, super.key});
  final UsageGateway gateway;

  @override
  State<DataLensHome> createState() => _DataLensHomeState();
}

class _DataLensHomeState extends State<DataLensHome>
    with WidgetsBindingObserver {
  late final UsageController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = UsageController(widget.gateway)..initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.refreshData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => OverviewScreen(controller: controller),
  );
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({required this.controller, super.key});
  final UsageController controller;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  var _selectedNetwork = 'All';
  var _selectedDestination = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return AnduraPage(
      title: 'DataLens',
      actions: [
        AnduraNotificationButton(
          hasNotification: widget.controller.alerts.any(
            (alert) => alert.state == 'unread',
          ),
          onPressed: () => setState(() => _selectedDestination = 3),
        ),
        Padding(
          padding: EdgeInsets.only(right: tokens.space4),
          child: const AnduraUserAvatar(name: 'DataLens', radius: 17),
        ),
      ],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) =>
            setState(() => _selectedDestination = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps_rounded),
            label: 'Apps',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      child: switch (_selectedDestination) {
        1 => _AppsScreen(controller: widget.controller),
        2 => _HistoryScreen(controller: widget.controller),
        3 => _AlertsScreen(controller: widget.controller),
        4 => _SettingsScreen(controller: widget.controller),
        _ => _overview(tokens),
      },
    );
  }

  Widget _overview(AnduraThemeTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _OverviewHeader(
        tokens: tokens,
        monitoring: widget.controller.capabilities.monitoring,
      ),
      SizedBox(height: tokens.space4),
      if (!widget.controller.capabilities.monitoring) ...[
        AnduraAlert(
          title: widget.controller.capabilities.platform == 'android'
              ? 'Monitoring is off'
              : 'System-wide monitoring unavailable',
          message: widget.controller.capabilities.platform == 'android'
              ? 'Enable background monitoring to begin collecting usage locally.'
              : 'This platform does not expose Android-equivalent device and per-app counters.',
          action: widget.controller.capabilities.platform == 'android'
              ? AnduraButton(
                  label: 'Enable monitoring',
                  onPressed: widget.controller.startMonitoring,
                )
              : null,
        ),
        SizedBox(height: tokens.space4),
      ],
      _NetworkFilters(
        selected: _selectedNetwork,
        onSelected: (value) {
          setState(() => _selectedNetwork = value);
          widget.controller.setNetwork(value);
        },
      ),
      SizedBox(height: tokens.space4),
      _LiveSpeedCard(controller: widget.controller),
      SizedBox(height: tokens.space4),
      _UsageSummary(controller: widget.controller),
      SizedBox(height: tokens.space4),
      _HotspotCard(controller: widget.controller),
      if (widget.controller.network == 'all') ...[
        SizedBox(height: tokens.space4),
        _TrafficCategoriesCard(controller: widget.controller),
      ],
      SizedBox(height: tokens.space6),
      const AnduraSectionHeader(title: 'Data plan', action: 'Manage'),
      SizedBox(height: tokens.space3),
      _DataPlanCard(controller: widget.controller),
      SizedBox(height: tokens.space6),
      const AnduraSectionHeader(title: 'Last 7 days', action: 'History'),
      SizedBox(height: tokens.space3),
      _UsageChartCard(records: widget.controller.dailyUsage),
      SizedBox(height: tokens.space6),
      const AnduraSectionHeader(title: 'Top apps today', action: 'See all'),
      SizedBox(height: tokens.space3),
      _TopAppsCard(
        records: widget.controller.apps,
        hotspotSelected: widget.controller.network == 'hotspot',
      ),
      if (widget.controller.error != null) ...[
        SizedBox(height: tokens.space4),
        AnduraAlert(
          title: 'Data unavailable',
          message: widget.controller.error!,
          intent: AnduraIntent.danger,
        ),
      ],
    ],
  );
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.tokens, required this.monitoring});

  final AnduraThemeTokens tokens;
  final bool monitoring;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel =
        '${_weekday(now.weekday).toUpperCase()}, ${_monthName(now.month).toUpperCase()} ${now.day}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: tokens.space1),
              Text(
                'Overview',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surfaceWarm,
            borderRadius: BorderRadius.circular(tokens.radiusPill),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space3,
              vertical: tokens.space2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: monitoring ? tokens.success : tokens.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: tokens.space2),
                Text(
                  monitoring ? 'Live' : 'Off',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkFilters extends StatelessWidget {
  const _NetworkFilters({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final value in const ['All', 'Mobile', 'Wi-Fi', 'Hotspot']) ...[
            AnduraChip(
              label: value,
              selected: value == selected,
              avatar: value == 'Mobile'
                  ? const Icon(Icons.signal_cellular_alt, size: 16)
                  : value == 'Wi-Fi'
                  ? const Icon(Icons.wifi, size: 16)
                  : value == 'Hotspot'
                  ? const Icon(Icons.wifi_tethering, size: 16)
                  : null,
              onSelected: (_) => onSelected(value),
            ),
            if (value != 'Hotspot') const SizedBox(width: AnduraSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _LiveSpeedCard extends StatelessWidget {
  const _LiveSpeedCard({required this.controller});
  final UsageController controller;

  List<String> _parts(double? value) {
    if (value == null) return const ['—', ''];
    final formatted = formatBitsPerSecond(value);
    final index = formatted.indexOf(' ');
    return index < 0
        ? [formatted, '']
        : [formatted.substring(0, index), formatted.substring(index + 1)];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final down = _parts(controller.downloadBitsPerSecond);
    final up = _parts(controller.uploadBitsPerSecond);
    final available = controller.capabilities.monitoring;
    return AnduraCard(
      color: tokens.accent,
      padding: EdgeInsets.all(tokens.space6),
      onTap: available || controller.capabilities.platform != 'android'
          ? null
          : controller.startMonitoring,
      child: Semantics(
        label: available
            ? 'Live speed. Download ${down.join(' ')}. Upload ${up.join(' ')}.'
            : 'Live speed unavailable because monitoring is off.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed_rounded, color: tokens.accentOn, size: 20),
                  SizedBox(width: tokens.space2),
                  Text(
                    'LIVE SPEED',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.accentOn.withValues(alpha: .78),
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    available ? Icons.circle : Icons.play_arrow_rounded,
                    color: tokens.accentOn.withValues(alpha: .72),
                    size: 18,
                  ),
                ],
              ),
              SizedBox(height: tokens.space6),
              Row(
                children: [
                  Expanded(
                    child: _SpeedValue(
                      icon: Icons.south_rounded,
                      value: down[0],
                      unit: down[1],
                      label: 'Download',
                      color: tokens.accentOn,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 64,
                    color: tokens.accentOn.withValues(alpha: .22),
                  ),
                  SizedBox(width: tokens.space6),
                  Expanded(
                    child: _SpeedValue(
                      icon: Icons.north_rounded,
                      value: up[0],
                      unit: up[1],
                      label: 'Upload',
                      color: tokens.accentOn,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space4),
              Text(
                available
                    ? '${_networkLabel(controller.liveNetwork)}  •  Updated just now'
                    : 'Enable monitoring to measure live speed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.accentOn.withValues(alpha: .72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _networkLabel(String value) => switch (value) {
  'wifi' => 'Wi-Fi',
  'mobile' => 'Mobile',
  'vpn' => 'VPN',
  'other' => 'Other',
  _ => 'Network unknown',
};

class _SpeedValue extends StatelessWidget {
  const _SpeedValue({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unit,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: .78),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: color.withValues(alpha: .72)),
        ),
      ],
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final cycle = billingCycleFor(
      DateTime.now(),
      controller.plan?.cycleDay ?? 1,
    );
    return Row(
      children: [
        Expanded(
          child: AnduraCard(
            child: AnduraStat(
              label: 'USED TODAY',
              value: formatBytes(controller.today.totalBytes),
              change: controller.capabilities.latestSampleAt == null
                  ? 'Waiting for first sample'
                  : 'Local measured usage',
              intent: AnduraIntent.success,
            ),
          ),
        ),
        SizedBox(width: tokens.space3),
        Expanded(
          child: AnduraCard(
            child: AnduraStat(
              label: 'THIS CYCLE',
              value: formatBytes(controller.cycleUsage.totalBytes),
              change: '${cycle.daysRemaining} days remaining',
            ),
          ),
        ),
      ],
    );
  }
}

class _HotspotCard extends StatelessWidget {
  const _HotspotCard({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final hotspot = controller.hotspot;
    final statusLabel = hotspot.active
        ? 'Active'
        : hotspot.stateAvailable
        ? 'Off'
        : 'State unavailable';
    final duration = hotspot.sessionStartedAt == null
        ? null
        : DateTime.now().difference(hotspot.sessionStartedAt!);
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AppIcon(icon: Icons.wifi_tethering, color: tokens.accent),
              SizedBox(width: tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hotspot & tethering',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: tokens.space1),
                    Text(
                      hotspot.usageAvailable
                          ? '${formatBytes(hotspot.today.totalBytes)} today'
                          : 'Grant usage access to measure tethering',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              AnduraBadge(label: statusLabel),
            ],
          ),
          SizedBox(height: tokens.space4),
          Row(
            children: [
              Expanded(
                child: AnduraStat(
                  label: 'TODAY',
                  value: hotspot.usageAvailable
                      ? formatBytes(hotspot.today.totalBytes)
                      : '—',
                  change: hotspot.usageAvailable
                      ? '${formatBytes(hotspot.today.rxBytes)} down · ${formatBytes(hotspot.today.txBytes)} up'
                      : 'Usage unavailable',
                ),
              ),
              Expanded(
                child: AnduraStat(
                  label: 'CURRENT SESSION',
                  value: hotspot.active && hotspot.usageAvailable
                      ? formatBytes(hotspot.session.totalBytes)
                      : '—',
                  change: hotspot.active && duration != null
                      ? _durationLabel(duration)
                      : hotspot.stateAvailable
                      ? 'Hotspot is off'
                      : 'Status requires Android 11+',
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space3),
          AnduraListItem(
            leading: Icon(Icons.calendar_month_outlined, color: tokens.accent),
            title: const Text('This month'),
            subtitle: Text(
              '${formatBytes(hotspot.month.rxBytes)} down · ${formatBytes(hotspot.month.txBytes)} up',
            ),
            trailing: Text(
              hotspot.usageAvailable
                  ? formatBytes(hotspot.month.totalBytes)
                  : '—',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(height: tokens.space2),
          Text(
            'Select the Hotspot filter for daily history. Aggregate forwarded traffic only; apps on connected devices cannot be identified.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}

String _durationLabel(Duration value) {
  if (value.inHours > 0) {
    return '${value.inHours}h ${value.inMinutes.remainder(60)}m active';
  }
  return '${value.inMinutes.clamp(0, 59)}m active';
}

class _TrafficCategoriesCard extends StatelessWidget {
  const _TrafficCategoriesCard({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final apps = controller.apps.fold<int>(
      0,
      (total, app) => total + app.totalBytes,
    );
    final tethering = controller.hotspot.today.totalBytes;
    final remainder = controller.today.totalBytes - apps - tethering;
    final system = remainder > 0 ? remainder : 0;
    final rows = [
      (Icons.apps_rounded, 'Phone apps', apps),
      (Icons.wifi_tethering, 'Hotspot & tethering', tethering),
      (Icons.memory_rounded, 'System or unattributed', system),
    ];
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today by category',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: tokens.space2),
          Text(
            'App and tethering counters are reconciled by Android and may update later.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.space3),
          for (var index = 0; index < rows.length; index++) ...[
            AnduraListItem(
              leading: Icon(rows[index].$1, color: tokens.accent),
              title: Text(rows[index].$2),
              trailing: Text(
                formatBytes(rows[index].$3),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (index != rows.length - 1) const AnduraDivider(),
          ],
        ],
      ),
    );
  }
}

class _DataPlanCard extends StatelessWidget {
  const _DataPlanCard({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final plan = controller.plan;
    if (plan == null || !plan.enabled) {
      return AnduraCard(
        child: AnduraEmptyState(
          message: 'No mobile data plan configured',
          icon: Icons.data_usage_rounded,
        ),
      );
    }
    final progress = (controller.cycleUsage.totalBytes / plan.capBytes).clamp(
      0.0,
      1.0,
    );
    final cycle = billingCycleFor(DateTime.now(), plan.cycleDay);
    final reset = '${_monthName(cycle.end.month)} ${cycle.end.day}';
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                ),
                child: Icon(Icons.data_usage_rounded, color: tokens.accent),
              ),
              SizedBox(width: tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly mobile plan',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: tokens.space1),
                    Text(
                      'Resets $reset',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              AnduraBadge(label: '${(progress * 100).round()}%'),
            ],
          ),
          SizedBox(height: tokens.space4),
          AnduraProgress(value: progress),
          SizedBox(height: tokens.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatBytes(controller.cycleUsage.totalBytes)} used',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                formatBytes(plan.capBytes, fractionDigits: 0),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _monthName(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

class _UsageChartCard extends StatelessWidget {
  const _UsageChartCard({required this.records});
  final List<DailyUsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final now = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - index)),
    );
    final bytes = days
        .map(
          (day) => records
              .where(
                (record) =>
                    record.date.year == day.year &&
                    record.date.month == day.month &&
                    record.date.day == day.day,
              )
              .fold<int>(0, (sum, record) => sum + record.total.totalBytes),
        )
        .toList();
    final maxBytes = bytes.fold<int>(
      0,
      (largest, value) => value > largest ? value : largest,
    );
    final total = bytes.fold<int>(0, (sum, value) => sum + value);
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatBytes(total),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: tokens.space2),
              Text(
                'total',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              const Spacer(),
              _Legend(color: tokens.accent, label: 'Usage'),
            ],
          ),
          SizedBox(height: tokens.space6),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < days.length; index++)
                  Expanded(
                    child: _ChartBar(
                      label: _weekday(days[index].weekday),
                      value: maxBytes == 0 ? 0 : bytes[index] / maxBytes,
                      bytes: bytes[index],
                      selected: index == days.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyUsageChartCard extends StatelessWidget {
  const _HourlyUsageChartCard({required this.records});
  final List<HourlyUsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final hours = _last24Hours(records);
    final bytes = hours.map((record) => record.total.totalBytes).toList();
    final maxBytes = bytes.fold<int>(
      0,
      (largest, value) => value > largest ? value : largest,
    );
    final total = bytes.fold<int>(0, (sum, value) => sum + value);
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatBytes(total),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: tokens.space2),
              Text(
                'last 24 hours',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              const Spacer(),
              _Legend(color: tokens.accent, label: 'Usage'),
            ],
          ),
          SizedBox(height: tokens.space6),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < hours.length; index++)
                  Expanded(
                    child: _ChartBar(
                      label: hours[index].hour.hour % 4 == 0
                          ? hours[index].hour.hour.toString().padLeft(2, '0')
                          : '',
                      semanticsLabel: _hourLabel(hours[index].hour),
                      value: maxBytes == 0 ? 0 : bytes[index] / maxBytes,
                      bytes: bytes[index],
                      selected: index == hours.length - 1,
                      barWidth: 8,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<HourlyUsageRecord> _last24Hours(List<HourlyUsageRecord> records) {
  final now = DateTime.now();
  final currentHour = DateTime(now.year, now.month, now.day, now.hour);
  return List.generate(24, (index) {
    final hour = currentHour.subtract(Duration(hours: 23 - index));
    final total = records
        .where((record) => _isSameHour(record.hour, hour))
        .fold<UsageTotal>(
          const UsageTotal(),
          (sum, record) => UsageTotal(
            rxBytes: sum.rxBytes + record.total.rxBytes,
            txBytes: sum.txBytes + record.total.txBytes,
          ),
        );
    return HourlyUsageRecord(hour: hour, total: total);
  });
}

bool _isSameHour(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day &&
    first.hour == second.hour;

String _hourLabel(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '$hour:00 ${value.hour < 12 ? 'AM' : 'PM'}';
}

String _weekday(int day) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1];

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
    required this.label,
    required this.value,
    required this.bytes,
    required this.selected,
    this.semanticsLabel,
    this.barWidth = 16,
  });

  final String label;
  final String? semanticsLabel;
  final double value;
  final int bytes;
  final bool selected;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return Semantics(
      label: '${semanticsLabel ?? label} ${formatBytes(bytes)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: value,
                child: Container(
                  width: barWidth,
                  decoration: BoxDecoration(
                    color: selected
                        ? tokens.accent
                        : tokens.accent.withValues(alpha: .25),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(tokens.radiusPill),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.space2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? tokens.foreground : tokens.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopAppsCard extends StatelessWidget {
  const _TopAppsCard({required this.records, required this.hotspotSelected});
  final List<AppUsageRecord> records;
  final bool hotspotSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final visible = records.take(3).toList();
    if (visible.isEmpty) {
      return AnduraCard(
        child: AnduraEmptyState(
          message: hotspotSelected
              ? 'Android cannot identify apps used on connected devices.'
              : 'Grant usage access, then reconcile to see per-app usage.',
          icon: Icons.apps_outlined,
        ),
      );
    }
    final colors = [tokens.danger, tokens.accent, tokens.success];
    return AnduraCard(
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            AnduraListItem(
              leading: _AppIcon(
                icon: Icons.android_rounded,
                color: colors[index],
              ),
              title: Text(
                visible[index].label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${visible[index].foregroundState} · ${formatBytes(visible[index].rxBytes)} down',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatBytes(visible[index].totalBytes),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: tokens.space1),
                  Icon(Icons.chevron_right, color: tokens.muted, size: 20),
                ],
              ),
              onTap: () {},
            ),
            if (index != visible.length - 1) const AnduraDivider(),
          ],
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _AppsScreen extends StatefulWidget {
  const _AppsScreen({required this.controller});
  final UsageController controller;

  @override
  State<_AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<_AppsScreen> {
  var query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final records = widget.controller.apps
        .where((app) => app.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Apps',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: tokens.space2),
        Text(
          'Usage attributed by Android system counters',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
        ),
        SizedBox(height: tokens.space4),
        if (widget.controller.capabilities.usageAccess) ...[
          AnduraButton(
            label: 'Refresh app usage',
            icon: Icons.sync,
            loading: widget.controller.loading,
            onPressed: widget.controller.reconcile,
          ),
          SizedBox(height: tokens.space4),
        ],
        if (!widget.controller.capabilities.usageAccess) ...[
          AnduraAlert(
            title: 'Usage access needed',
            message:
                'Android requires usage access to show per-app totals. DataLens never reads traffic contents.',
            intent: AnduraIntent.warning,
            action: AnduraButton(
              label: 'Open system settings',
              onPressed: widget.controller.openUsageSettings,
            ),
          ),
          SizedBox(height: tokens.space3),
          AnduraButton(
            label: 'Check access and reconcile',
            onPressed: widget.controller.reconcile,
          ),
          SizedBox(height: tokens.space4),
        ],
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search apps',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        SizedBox(height: tokens.space4),
        if (records.isEmpty)
          const AnduraCard(
            child: AnduraEmptyState(
              message: 'No attributed app usage in this period',
              icon: Icons.apps_outlined,
            ),
          )
        else
          AnduraCard(
            child: Column(
              children: [
                for (var index = 0; index < records.length; index++) ...[
                  AnduraListItem(
                    leading: _AppIcon(
                      icon: Icons.android,
                      color: tokens.accent,
                    ),
                    title: Text(
                      records[index].label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${formatBytes(records[index].rxBytes)} down · ${formatBytes(records[index].txBytes)} up',
                    ),
                    trailing: Text(
                      formatBytes(records[index].totalBytes),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _showAppDetails(context, records[index]),
                  ),
                  if (index != records.length - 1) const AnduraDivider(),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _showAppDetails(BuildContext context, AppUsageRecord app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final tokens = AnduraThemeTokens.of(context);
        return Padding(
          padding: EdgeInsets.all(tokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: tokens.space3),
              Text(app.packageName ?? 'Package unavailable'),
              SizedBox(height: tokens.space4),
              AnduraCard(
                child: Row(
                  children: [
                    Expanded(
                      child: AnduraStat(
                        label: 'DOWNLOAD',
                        value: formatBytes(app.rxBytes),
                      ),
                    ),
                    Expanded(
                      child: AnduraStat(
                        label: 'UPLOAD',
                        value: formatBytes(app.txBytes),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.space3),
              Text(
                'Activity state: ${app.foregroundState}',
                style: TextStyle(color: tokens.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryScreen extends StatefulWidget {
  const _HistoryScreen({required this.controller});
  final UsageController controller;

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  var _hourly = true;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final hourlyRecords = _last24Hours(widget.controller.hourlyUsage);
    final recordsAvailable = _hourly
        ? widget.controller.hourlyUsage.isNotEmpty
        : widget.controller.dailyUsage.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'History',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: tokens.space2),
        Text(
          _hourly
              ? 'Measured device totals for the last 24 hours'
              : 'Measured device totals for the last 7 days',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
        ),
        SizedBox(height: tokens.space4),
        Row(
          children: [
            AnduraChip(
              label: 'Hourly',
              selected: _hourly,
              onSelected: (_) => setState(() => _hourly = true),
            ),
            SizedBox(width: tokens.space2),
            AnduraChip(
              label: 'Daily',
              selected: !_hourly,
              onSelected: (_) => setState(() => _hourly = false),
            ),
          ],
        ),
        SizedBox(height: tokens.space4),
        if (_hourly)
          _HourlyUsageChartCard(records: widget.controller.hourlyUsage)
        else
          _UsageChartCard(records: widget.controller.dailyUsage),
        SizedBox(height: tokens.space4),
        AnduraSectionHeader(
          title: _hourly ? 'Hourly breakdown' : 'Daily breakdown',
        ),
        SizedBox(height: tokens.space3),
        if (!recordsAvailable)
          const AnduraCard(
            child: AnduraEmptyState(
              message: 'History appears after the first monitoring samples',
              icon: Icons.bar_chart_outlined,
            ),
          )
        else if (_hourly)
          _HourlyBreakdown(records: hourlyRecords)
        else
          _DailyBreakdown(records: widget.controller.dailyUsage),
      ],
    );
  }
}

class _HourlyBreakdown extends StatelessWidget {
  const _HourlyBreakdown({required this.records});
  final List<HourlyUsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final now = DateTime.now();
    return AnduraCard(
      child: Column(
        children: [
          for (var index = records.length - 1; index >= 0; index--) ...[
            AnduraListItem(
              leading: _AppIcon(
                icon: Icons.schedule_outlined,
                color: tokens.accent,
              ),
              title: Text(_hourBreakdownLabel(records[index].hour, now)),
              subtitle: Text(
                '${formatBytes(records[index].total.rxBytes)} down · ${formatBytes(records[index].total.txBytes)} up',
              ),
              trailing: Text(
                formatBytes(records[index].total.totalBytes),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (index != 0) const AnduraDivider(),
          ],
        ],
      ),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  const _DailyBreakdown({required this.records});
  final List<DailyUsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return AnduraCard(
      child: Column(
        children: [
          for (var index = records.length - 1; index >= 0; index--) ...[
            AnduraListItem(
              leading: _AppIcon(
                icon: Icons.calendar_today_outlined,
                color: tokens.accent,
              ),
              title: Text(
                '${_monthName(records[index].date.month)} ${records[index].date.day}',
              ),
              subtitle: Text(
                '${formatBytes(records[index].total.rxBytes)} down · ${formatBytes(records[index].total.txBytes)} up',
              ),
              trailing: Text(
                formatBytes(records[index].total.totalBytes),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (index != 0) const AnduraDivider(),
          ],
        ],
      ),
    );
  }
}

String _hourBreakdownLabel(DateTime value, DateTime now) {
  final day = DateTime(value.year, value.month, value.day);
  final today = DateTime(now.year, now.month, now.day);
  final dayLabel = day == today
      ? 'Today'
      : day == today.subtract(const Duration(days: 1))
      ? 'Yesterday'
      : '${_monthName(value.month)} ${value.day}';
  return '$dayLabel · ${_hourLabel(value)}';
}

class _AlertsScreen extends StatelessWidget {
  const _AlertsScreen({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Alerts',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: tokens.space2),
        Text(
          'Deduplicated data-plan notifications',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
        ),
        SizedBox(height: tokens.space4),
        if (controller.alerts.isEmpty)
          const AnduraCard(
            child: AnduraEmptyState(
              message: 'No alerts yet',
              icon: Icons.notifications_none,
            ),
          )
        else
          for (final alert in controller.alerts) ...[
            AnduraAlert(
              title: alert.type == 'plan_100'
                  ? 'Data plan reached'
                  : 'Data plan at 80%',
              message:
                  '${formatBytes(alert.actualBytes)} used in this billing cycle.',
              intent: alert.type == 'plan_100'
                  ? AnduraIntent.danger
                  : AnduraIntent.warning,
            ),
            SizedBox(height: tokens.space3),
          ],
      ],
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.controller});
  final UsageController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final capability = controller.capabilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: tokens.space4),
        const AnduraSectionHeader(title: 'Monitoring'),
        SizedBox(height: tokens.space3),
        AnduraCard(
          child: Column(
            children: [
              AnduraSwitch(
                label: 'Background monitoring',
                subtitle:
                    'Stores local snapshots every minute and shows a persistent notification',
                value: capability.monitoring,
                enabled: capability.platform == 'android',
                onChanged: (enabled) => enabled
                    ? controller.startMonitoring()
                    : controller.stopMonitoring(),
              ),
              const AnduraDivider(),
              _CapabilityRow(
                label: 'Usage access',
                available: capability.usageAccess,
                needed: true,
              ),
              _CapabilityRow(
                label: 'Notifications',
                available: capability.notifications,
                needed: true,
              ),
              _CapabilityRow(
                label: 'Latest sample',
                available: capability.latestSampleAt != null,
                detail: _sampleLabel(capability.latestSampleAt),
              ),
              _CapabilityRow(
                label: 'Hotspot state',
                available: controller.hotspot.stateAvailable,
                detail: controller.hotspot.active
                    ? 'Active'
                    : controller.hotspot.stateAvailable
                    ? 'Off'
                    : 'Unavailable on this device',
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space3),
        if (!capability.usageAccess)
          AnduraButton(
            label: 'Grant usage access',
            icon: Icons.admin_panel_settings_outlined,
            onPressed: controller.openUsageSettings,
          ),
        if (capability.usageAccess)
          AnduraButton(
            label: 'Reconcile app usage now',
            icon: Icons.sync,
            loading: controller.loading,
            onPressed: controller.reconcile,
          ),
        SizedBox(height: tokens.space6),
        const AnduraSectionHeader(title: 'Plan and privacy'),
        SizedBox(height: tokens.space3),
        AnduraSettingsTile(
          icon: Icons.data_usage_rounded,
          color: tokens.accent,
          title: 'Data plan & billing cycle',
          trailing: Text(
            controller.plan == null
                ? 'Not set'
                : formatBytes(controller.plan!.capBytes, fractionDigits: 0),
          ),
          onTap: () => _showPlanDialog(context, controller),
        ),
        AnduraSettingsTile(
          icon: Icons.delete_outline,
          color: tokens.danger,
          title: 'Delete all local data',
          onTap: () => _confirmDelete(context, controller),
        ),
        AnduraAlert(
          title: 'Local and private',
          message:
              'DataLens stores byte counters and app labels on this device. It never inspects payloads, URLs, messages, or browsing history.',
          intent: AnduraIntent.info,
        ),
        SizedBox(height: tokens.space3),
        Text(
          'Android foundation · Phase 2',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      ],
    );
  }

  String _sampleLabel(DateTime? value) {
    if (value == null) return 'Waiting for first sample';
    final elapsed = DateTime.now().difference(value);
    if (elapsed.inMinutes < 2) return 'Available · just now';
    return 'Stale · ${elapsed.inMinutes} minutes ago';
  }

  Future<void> _showPlanDialog(
    BuildContext context,
    UsageController controller,
  ) async {
    final cap = TextEditingController(
      text: controller.plan == null
          ? '30'
          : (controller.plan!.capBytes / 1000 / 1000 / 1000).toStringAsFixed(0),
    );
    final day = TextEditingController(
      text: '${controller.plan?.cycleDay ?? 1}',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mobile data plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cap,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Plan size (GB)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: day,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Billing cycle day (1–31)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final gb = double.tryParse(cap.text);
              final cycleDay = int.tryParse(day.text);
              if (gb == null ||
                  gb <= 0 ||
                  cycleDay == null ||
                  cycleDay < 1 ||
                  cycleDay > 31) {
                return;
              }
              controller.updatePlan(
                DataPlan(
                  capBytes: (gb * 1000 * 1000 * 1000).round(),
                  cycleDay: cycleDay,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    cap.dispose();
    day.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UsageController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all local data?'),
        content: const Text(
          'This removes usage history, app identities, alerts, and your data plan. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteAllData();
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.available,
    this.needed = false,
    this.detail,
  });
  final String label;
  final bool available;
  final bool needed;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final status =
        detail ??
        (available
            ? 'Available'
            : needed
            ? 'Permission needed'
            : 'Unavailable');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space3),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle_outline : Icons.info_outline,
            color: available ? tokens.success : tokens.warning,
          ),
          SizedBox(width: tokens.space3),
          Expanded(child: Text(label)),
          Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}
