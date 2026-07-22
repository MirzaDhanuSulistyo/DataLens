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
}
