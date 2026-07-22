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
          onPressed: () => widget.controller.selectDestination(3),
        ),
        Padding(
          padding: EdgeInsets.only(right: tokens.space4),
          child: const AnduraUserAvatar(name: 'DataLens', radius: 17),
        ),
      ],
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.controller.selectedDestination,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: widget.controller.selectDestination,
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
      child: switch (widget.controller.selectedDestination) {
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
              onPressed: () =>
                  _showUsageAccessDisclosure(context, widget.controller),
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
    var excludedFromAlerts = app.excludedFromAlerts;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final tokens = AnduraThemeTokens.of(context);
          return SafeArea(
            child: SingleChildScrollView(
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
                  SizedBox(height: tokens.space2),
                  Text(
                    app.baselineMature
                        ? 'Usual daily usage: ${formatBytes(app.baselineBytes ?? 0)} · ${app.baselineSampleCount} complete days learned'
                        : 'Baseline learning: ${app.baselineSampleCount} of 7 complete days',
                    style: TextStyle(color: tokens.muted),
                  ),
                  const AnduraDivider(),
                  AnduraSwitch(
                    label: 'Exclude from intelligence alerts',
                    subtitle:
                        'Usage remains in totals and history, but unusual, new-app, and background alerts are suppressed.',
                    value: excludedFromAlerts,
                    onChanged: (value) async {
                      setSheetState(() => excludedFromAlerts = value);
                      await widget.controller.setAppExcluded(app.id, value);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
          'Plan, unusual usage, new-app, and background signals',
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
              title: _alertTitle(alert),
              message: _alertMessage(alert),
              intent: _alertIntent(alert),
            ),
            SizedBox(height: tokens.space3),
          ],
      ],
    );
  }
}

String _alertTitle(AlertRecord alert) => switch (alert.type) {
  'plan_100' => 'Data plan reached',
  'plan_80' => 'Data plan at 80%',
  'new_app' => 'New app using data',
  'anomaly_daily' => 'Unusual data usage',
  'background_usage' => 'Background data usage',
  _ => 'Usage alert',
};

String _alertMessage(AlertRecord alert) {
  if (alert.type.startsWith('plan_')) {
    return '${formatBytes(alert.actualBytes)} used in this billing cycle.';
  }
  final app = alert.appLabel ?? 'An app';
  final network = alert.networkType == null ? '' : ' on ${alert.networkType}';
  final comparison = alert.ratio == null
      ? ''
      : ' — ${alert.ratio!.toStringAsFixed(1)}× its usual rate';
  final state = alert.type == 'background_usage'
      ? ' while Android reported it in the background'
      : '';
  return '$app used ${formatBytes(alert.actualBytes)}$network$state$comparison.';
}

AnduraIntent _alertIntent(AlertRecord alert) => switch (alert.type) {
  'plan_100' || 'anomaly_daily' => AnduraIntent.danger,
  'plan_80' || 'background_usage' => AnduraIntent.warning,
  _ => AnduraIntent.info,
};

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
            onPressed: () => _showUsageAccessDisclosure(context, controller),
          ),
        if (capability.usageAccess)
          AnduraButton(
            label: 'Reconcile app usage now',
            icon: Icons.sync,
            loading: controller.loading,
            onPressed: controller.reconcile,
          ),
        if (capability.platform == 'android') ...[
          SizedBox(height: tokens.space6),
          const AnduraSectionHeader(title: 'Device setup'),
          SizedBox(height: tokens.space3),
          AnduraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  controller.deviceGuidance.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: tokens.space1),
                Text(
                  '${controller.deviceGuidance.manufacturer} ${controller.deviceGuidance.model} · Android ${controller.deviceGuidance.androidVersion}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                ),
                SizedBox(height: tokens.space3),
                for (final step in controller.deviceGuidance.steps)
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.space2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(step)),
                      ],
                    ),
                  ),
                SizedBox(height: tokens.space2),
                AnduraButton(
                  label: controller.deviceGuidance.optimizationExempt
                      ? 'Review battery settings'
                      : 'Open battery optimization settings',
                  icon: Icons.battery_saver_outlined,
                  onPressed: controller.openBatterySettings,
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: tokens.space6),
        const AnduraSectionHeader(title: 'Usage intelligence'),
        SizedBox(height: tokens.space3),
        AnduraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Alert sensitivity',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: tokens.space3),
              Wrap(
                spacing: tokens.space2,
                runSpacing: tokens.space2,
                children: [
                  for (final value in const ['off', 'low', 'medium', 'high'])
                    AnduraChip(
                      label: '${value[0].toUpperCase()}${value.substring(1)}',
                      selected:
                          controller.alertPreferences.sensitivity == value,
                      onSelected: (_) => controller.updateAlertPreferences(
                        controller.alertPreferences.copyWith(
                          sensitivity: value,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: tokens.space3),
              Text(
                'Baselines learn locally after 7 complete days and use robust per-app comparisons.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
              const AnduraDivider(),
              AnduraSwitch(
                label: 'Unusual usage alerts',
                subtitle: 'Ratio and minimum-byte thresholds',
                value: controller.alertPreferences.anomalyAlerts,
                onChanged: (value) => controller.updateAlertPreferences(
                  controller.alertPreferences.copyWith(anomalyAlerts: value),
                ),
              ),
              const AnduraDivider(),
              AnduraSwitch(
                label: 'New-app traffic alerts',
                subtitle:
                    'Once when a newly seen app first uses meaningful data',
                value: controller.alertPreferences.newAppAlerts,
                onChanged: (value) => controller.updateAlertPreferences(
                  controller.alertPreferences.copyWith(newAppAlerts: value),
                ),
              ),
              const AnduraDivider(),
              AnduraSwitch(
                label: 'Background usage alerts',
                subtitle: 'Only when Android reports a background state',
                value: controller.alertPreferences.backgroundAlerts,
                onChanged: (value) => controller.updateAlertPreferences(
                  controller.alertPreferences.copyWith(backgroundAlerts: value),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space6),
        const AnduraSectionHeader(title: 'Live speed overlay'),
        SizedBox(height: tokens.space3),
        AnduraCard(
          child: Column(
            children: [
              AnduraSwitch(
                label: 'Floating speed bubble',
                subtitle: capability.overlayPermission
                    ? 'Draggable and dismissible; monitoring must be active'
                    : 'Requires Android display-over-other-apps permission',
                value: capability.overlayEnabled,
                enabled: capability.platform == 'android',
                onChanged: controller.setOverlayEnabled,
              ),
              if (!capability.overlayPermission) ...[
                const AnduraDivider(),
                AnduraButton(
                  label: 'Grant overlay permission',
                  icon: Icons.open_in_new,
                  onPressed: controller.openOverlaySettings,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: tokens.space6),
        const AnduraSectionHeader(title: 'Home screen widget'),
        SizedBox(height: tokens.space3),
        AnduraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Widget content',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: tokens.space3),
              Wrap(
                spacing: tokens.space2,
                runSpacing: tokens.space2,
                children: [
                  AnduraChip(
                    label: 'Today',
                    selected: controller.widgetPreferences.content == 'today',
                    onSelected: (_) => controller.updateWidgetPreferences(
                      controller.widgetPreferences.copyWith(content: 'today'),
                    ),
                  ),
                  AnduraChip(
                    label: 'Billing cycle',
                    selected: controller.widgetPreferences.content == 'cycle',
                    onSelected: (_) => controller.updateWidgetPreferences(
                      controller.widgetPreferences.copyWith(content: 'cycle'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space4),
              Text(
                'Refresh while monitoring',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: tokens.space3),
              Wrap(
                spacing: tokens.space2,
                runSpacing: tokens.space2,
                children: [
                  for (final minutes in const [15, 30, 60])
                    AnduraChip(
                      label: '$minutes min',
                      selected:
                          controller.widgetPreferences.refreshMinutes ==
                          minutes,
                      onSelected: (_) => controller.updateWidgetPreferences(
                        controller.widgetPreferences.copyWith(
                          refreshMinutes: minutes,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: tokens.space3),
              Semantics(
                label:
                    'Widget preview. ${controller.widgetPreferences.content == 'cycle' ? 'Billing cycle' : 'Today'} usage ${formatBytes(controller.widgetPreferences.content == 'cycle' ? controller.cycleUsage.totalBytes : controller.today.totalBytes)}.',
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surfaceWarm,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(tokens.space4),
                      child: Row(
                        children: [
                          Icon(Icons.data_usage_rounded, color: tokens.accent),
                          SizedBox(width: tokens.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.widgetPreferences.content ==
                                          'cycle'
                                      ? 'THIS BILLING CYCLE'
                                      : 'USED TODAY',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(
                                  formatBytes(
                                    controller.widgetPreferences.content ==
                                            'cycle'
                                        ? controller.cycleUsage.totalBytes
                                        : controller.today.totalBytes,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const Text('DataLens'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: tokens.space3),
              Text(
                'Add DataLens from the Android widget picker. Android may defer updates to protect battery; every value includes its last-updated time.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ),
        if (capability.platform == 'android') ...[
          SizedBox(height: tokens.space6),
          const AnduraSectionHeader(title: 'Data portability'),
          SizedBox(height: tokens.space2),
          Text(
            'Export spreadsheet data or move all local DataLens data between Android devices.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.muted),
          ),
          SizedBox(height: tokens.space3),
          AnduraSettingsTile(
            icon: Icons.table_view_outlined,
            color: tokens.accent,
            title: 'Export usage as CSV',
            onTap: controller.dataOperationInProgress
                ? null
                : controller.exportCsv,
          ),
          AnduraSettingsTile(
            icon: Icons.backup_outlined,
            color: tokens.accent,
            title: 'Create local backup',
            onTap: controller.dataOperationInProgress
                ? null
                : controller.createBackup,
          ),
          AnduraSettingsTile(
            icon: Icons.settings_backup_restore,
            color: tokens.warning,
            title: 'Restore local backup',
            onTap: controller.dataOperationInProgress
                ? null
                : () => _confirmRestore(context, controller),
          ),
          if (controller.dataOperationInProgress)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (controller.dataOperationMessage != null)
            AnduraAlert(
              title: 'Data portability',
              message: controller.dataOperationMessage!,
              intent: AnduraIntent.info,
            ),
        ],
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
          icon: Icons.history_toggle_off_rounded,
          color: tokens.accent,
          title: 'History retention',
          trailing: Text(
            controller.retentionDays < 0
                ? 'Forever'
                : '${controller.retentionDays} days',
          ),
          onTap: () => _showRetentionDialog(context, controller),
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
          'Android P2 · Portability and compatibility',
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

  Future<void> _showRetentionDialog(
    BuildContext context,
    UsageController controller,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('History retention'),
        children: [
          RadioGroup<int>(
            groupValue: controller.retentionDays,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in const [30, 90, 365, -1])
                  RadioListTile<int>(
                    title: Text(
                      option < 0 ? 'Keep forever' : 'Keep $option days',
                    ),
                    subtitle: option == 30
                        ? const Text('Uses the least local storage')
                        : null,
                    value: option,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) await controller.updateRetentionDays(selected);
  }

  Future<void> _confirmRestore(
    BuildContext context,
    UsageController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore a local backup?'),
        content: const Text(
          'Restoring replaces all current usage history, app identities, alerts, plans, preferences, and exclusions. Create a current backup first if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.restoreBackup();
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

Future<void> _showUsageAccessDisclosure(
  BuildContext context,
  UsageController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow usage access?'),
      content: const Text(
        'DataLens uses Android usage access to read byte totals reported by the operating system and attribute them to apps. This data stays on this device. DataLens does not inspect network payloads, URLs, messages, or browsing history. You can revoke access at any time in Android Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.openUsageSettings();
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
