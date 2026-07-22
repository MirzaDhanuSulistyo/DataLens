import 'package:datalens/core/platform/usage_gateway.dart';
import 'package:datalens/main.dart';
import 'package:flutter/material.dart';
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

  testWidgets('app details can exclude an app from intelligence alerts', (
    tester,
  ) async {
    final gateway = FakeUsageGateway();
    await tester.pumpWidget(DataLensApp(gateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apps').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser').last);
    await tester.pumpAndSettle();

    expect(find.text('Exclude from intelligence alerts'), findsOneWidget);
    await tester.ensureVisible(find.text('Exclude from intelligence alerts'));
    await tester.tap(find.text('Exclude from intelligence alerts'));
    await tester.pumpAndSettle();

    expect(gateway.appRecords.single.excludedFromAlerts, isTrue);
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

  testWidgets('all unread alerts can be marked as read', (tester) async {
    final gateway = FakeUsageGateway()
      ..initialDestinationValue = 'alerts'
      ..alertRecords = [
        AlertRecord(
          id: 7,
          type: 'anomaly_daily',
          actualBytes: 200000000,
          state: 'unread',
          createdAt: DateTime.now(),
          appLabel: 'Browser',
        ),
        AlertRecord(
          id: 8,
          type: 'plan_80',
          actualBytes: 24000000000,
          state: 'unread',
          createdAt: DateTime.now(),
        ),
      ];
    await tester.pumpWidget(DataLensApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('Mark all as read'), findsOneWidget);
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    expect(
      gateway.alertRecords.every((alert) => alert.state == 'read'),
      isTrue,
    );
    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('settings exposes widget, portability, and OEM controls', (
    tester,
  ) async {
    await tester.pumpWidget(DataLensApp(gateway: FakeUsageGateway()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Home screen widget'), findsOneWidget);
    expect(find.text('History retention'), findsOneWidget);
    expect(find.text('Google Pixel Test · Android 15'), findsOneWidget);
    expect(find.text('Export usage as CSV'), findsOneWidget);
    expect(find.text('Create local backup'), findsOneWidget);
    expect(find.text('Restore local backup'), findsOneWidget);
    expect(
      find.text('Android P2 · Portability and compatibility'),
      findsOneWidget,
    );
  });

  testWidgets('battery settings action fits on a narrow settings screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final gateway = FakeUsageGateway()
      ..initialDestinationValue = 'settings'
      ..capabilityStatus = CapabilityStatus(
        platform: 'android',
        usageAccess: false,
        notifications: true,
        monitoring: true,
        latestSampleAt: DateTime.now(),
        overlayPermission: true,
      );
    await tester.pumpWidget(DataLensApp(gateway: gateway));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open battery optimization settings'));
    await tester.pumpAndSettle();

    expect(find.text('Open battery optimization settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
