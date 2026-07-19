import 'package:andura_ui/andura_ui.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DataLensApp());

class DataLensApp extends StatelessWidget {
  const DataLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DataLens',
      debugShowCheckedModeBanner: false,
      theme: AnduraTheme.light,
      darkTheme: AnduraTheme.dark,
      themeMode: ThemeMode.light,
      home: const OverviewScreen(),
    );
  }
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  var _selectedNetwork = 'All';
  var _selectedDestination = 0;

  void _showPreviewMessage(String destination) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$destination will be available in the next prototype.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return AnduraPage(
      title: 'DataLens',
      actions: [
        AnduraNotificationButton(
          hasNotification: true,
          onPressed: () => _showPreviewMessage('Alerts'),
        ),
        Padding(
          padding: EdgeInsets.only(right: tokens.space4),
          child: const AnduraUserAvatar(name: 'Olseraios', radius: 17),
        ),
      ],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 0) {
            setState(() => _selectedDestination = index);
            return;
          }
          _showPreviewMessage(
            const ['Overview', 'Apps', 'History', 'Alerts', 'Settings'][index],
          );
        },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverviewHeader(tokens: tokens),
          SizedBox(height: tokens.space4),
          _NetworkFilters(
            selected: _selectedNetwork,
            onSelected: (value) => setState(() => _selectedNetwork = value),
          ),
          SizedBox(height: tokens.space4),
          const _LiveSpeedCard(),
          SizedBox(height: tokens.space4),
          const _UsageSummary(),
          SizedBox(height: tokens.space6),
          const AnduraSectionHeader(title: 'Data plan', action: 'Manage'),
          SizedBox(height: tokens.space3),
          const _DataPlanCard(),
          SizedBox(height: tokens.space6),
          const AnduraSectionHeader(title: 'Last 7 days', action: 'History'),
          SizedBox(height: tokens.space3),
          const _UsageChartCard(),
          SizedBox(height: tokens.space6),
          const AnduraSectionHeader(title: 'Top apps today', action: 'See all'),
          SizedBox(height: tokens.space3),
          const _TopAppsCard(),
          SizedBox(height: tokens.space4),
          AnduraAlert(
            title: 'Higher than usual',
            message: 'Instagram used 320 MB today — 2.4× its daily average.',
            intent: AnduraIntent.warning,
            action: AnduraLink(
              label: 'View details',
              icon: Icons.arrow_forward,
              trailingIcon: true,
              onPressed: () => _showPreviewMessage('Alert details'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.tokens});

  final AnduraThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONDAY, JUL 20',
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
                    color: tokens.success,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: tokens.space2),
                Text(
                  'Live',
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
          for (final value in const ['All', 'Mobile', 'Wi-Fi']) ...[
            AnduraChip(
              label: value,
              selected: value == selected,
              avatar: value == 'Mobile'
                  ? const Icon(Icons.signal_cellular_alt, size: 16)
                  : value == 'Wi-Fi'
                  ? const Icon(Icons.wifi, size: 16)
                  : null,
              onSelected: (_) => onSelected(value),
            ),
            if (value != 'Wi-Fi') const SizedBox(width: AnduraSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _LiveSpeedCard extends StatelessWidget {
  const _LiveSpeedCard();

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return AnduraCard(
      color: tokens.accent,
      padding: EdgeInsets.all(tokens.space6),
      onTap: () {},
      child: Semantics(
        label:
            'Live speed. Download 8.4 megabits per second. Upload 1.2 megabits per second.',
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
                    Icons.chevron_right,
                    color: tokens.accentOn.withValues(alpha: .72),
                  ),
                ],
              ),
              SizedBox(height: tokens.space6),
              Row(
                children: [
                  Expanded(
                    child: _SpeedValue(
                      icon: Icons.south_rounded,
                      value: '8.4',
                      unit: 'Mbps',
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
                      value: '1.2',
                      unit: 'Mbps',
                      label: 'Upload',
                      color: tokens.accentOn,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space4),
              Text(
                'Wi-Fi  •  Updated just now',
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
  const _UsageSummary();

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: AnduraCard(
            child: AnduraStat(
              label: 'USED TODAY',
              value: '1.28 GB',
              change: '↓ 12% vs yesterday',
              intent: AnduraIntent.success,
            ),
          ),
        ),
        SizedBox(width: tokens.space3),
        Expanded(
          child: AnduraCard(
            child: AnduraStat(
              label: 'THIS MONTH',
              value: '18.6 GB',
              change: '11 days remaining',
            ),
          ),
        ),
      ],
    );
  }
}

class _DataPlanCard extends StatelessWidget {
  const _DataPlanCard();

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
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
                      'Resets August 1',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
              const AnduraBadge(label: '62%'),
            ],
          ),
          SizedBox(height: tokens.space4),
          const AnduraProgress(value: .62),
          SizedBox(height: tokens.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '18.6 GB used',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '30 GB',
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

class _UsageChartCard extends StatelessWidget {
  const _UsageChartCard();

  static const _days = ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon'];
  static const _values = [.42, .65, .51, .88, .72, .58, .79];

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return AnduraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '8.9 GB',
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
              _Legend(color: tokens.accent, label: 'Mobile'),
              SizedBox(width: tokens.space3),
              _Legend(color: tokens.success, label: 'Wi-Fi'),
            ],
          ),
          SizedBox(height: tokens.space6),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < _days.length; index++)
                  Expanded(
                    child: _ChartBar(
                      label: _days[index],
                      value: _values[index],
                      selected: index == _days.length - 1,
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
    required this.selected,
  });

  final String label;
  final double value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    return Semantics(
      label: '$label ${(value * 2).toStringAsFixed(1)} gigabytes',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: value,
                child: Container(
                  width: 16,
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
  const _TopAppsCard();

  @override
  Widget build(BuildContext context) {
    final tokens = AnduraThemeTokens.of(context);
    final apps = [
      _AppUsage(
        'Instagram',
        'Social · 38% of today',
        '486 MB',
        Icons.camera_alt_outlined,
        tokens.danger,
      ),
      _AppUsage(
        'YouTube',
        'Entertainment · 26%',
        '332 MB',
        Icons.play_arrow_rounded,
        tokens.accent,
      ),
      _AppUsage(
        'Safari',
        'Browser · 17%',
        '218 MB',
        Icons.language_rounded,
        tokens.success,
      ),
    ];
    return AnduraCard(
      child: Column(
        children: [
          for (var index = 0; index < apps.length; index++) ...[
            AnduraListItem(
              leading: _AppIcon(
                icon: apps[index].icon,
                color: apps[index].color,
              ),
              title: Text(
                apps[index].name,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(apps[index].detail),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    apps[index].usage,
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
            if (index != apps.length - 1) const AnduraDivider(),
          ],
        ],
      ),
    );
  }
}

class _AppUsage {
  const _AppUsage(this.name, this.detail, this.usage, this.icon, this.color);

  final String name;
  final String detail;
  final String usage;
  final IconData icon;
  final Color color;
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
