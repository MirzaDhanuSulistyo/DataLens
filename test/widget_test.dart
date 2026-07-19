import 'package:datalens/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overview shows primary usage information', (tester) async {
    await tester.pumpWidget(const DataLensApp());
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsAtLeastNWidgets(1));
    expect(find.text('LIVE SPEED'), findsOneWidget);
    expect(find.text('1.28 GB'), findsOneWidget);
    expect(find.text('Monthly mobile plan'), findsOneWidget);
    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('History'), findsAtLeastNWidgets(1));
  });
}
