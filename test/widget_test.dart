import 'package:datalens/main.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_usage_gateway.dart';

void main() {
  testWidgets('overview shows measured usage information', (tester) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsAtLeastNWidgets(1));
    expect(find.text('LIVE SPEED'), findsOneWidget);
    expect(find.text('1.3 GB'), findsAtLeastNWidgets(1));
    expect(find.text('Monthly mobile plan'), findsOneWidget);
    expect(find.text('Hotspot & tethering'), findsAtLeastNWidgets(1));
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
  });

  testWidgets('overview supports large accessibility text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Overview'), findsAtLeastNWidgets(1));
  });

  testWidgets('hotspot filter separates tethering from phone apps', (
    tester,
  ) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hotspot'));
    await tester.pumpAndSettle();

    expect(find.text('240.0 MB'), findsAtLeastNWidgets(1));
    expect(
      find.text('Android cannot identify apps used on connected devices.'),
      findsOneWidget,
    );
  });

  testWidgets('bottom navigation opens the apps experience', (tester) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apps').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Usage attributed by Android system counters'),
      findsOneWidget,
    );
    expect(find.text('Search apps'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
  });

  testWidgets('initial deep link opens the requested destination', (
    tester,
  ) async {
    final gateway = FakeUsageGateway()..initialDestinationValue = 'alerts';
    await tester.pumpWidget(DataLensApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(
      find.text('Plan, unusual usage, new-app, and background signals'),
      findsOneWidget,
    );
  });

  testWidgets('settings exposes widget and retention controls', (tester) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Home screen widget'), findsOneWidget);
    expect(find.text('History retention'), findsOneWidget);
    expect(find.text('Widgets and hardening · Phase 4'), findsOneWidget);
  });

  testWidgets('history switches between hourly and daily usage', (
    tester,
  ) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Measured device totals for the last 24 hours'),
      findsOneWidget,
    );
    expect(find.text('Hourly breakdown'), findsOneWidget);

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    expect(
      find.text('Measured device totals for the last 7 days'),
      findsOneWidget,
    );
    expect(find.text('Daily breakdown'), findsOneWidget);
  });
}
