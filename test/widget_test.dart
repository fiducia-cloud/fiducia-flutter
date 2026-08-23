import 'package:fiducia_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell derives controls from the lifecycle snapshot', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FiduciaApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('signedOut'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Request protected action'), findsOneWidget);
  });
}
