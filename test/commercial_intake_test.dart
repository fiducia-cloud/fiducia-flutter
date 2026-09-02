import 'package:fiducia_flutter/main.dart';
import 'package:fiducia_flutter/src/commercial/commercial_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Fiducia renders before any commercial network request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CommercialIntakeHub()),
    );

    expect(
      find.byKey(const ValueKey<String>('fiducia-commercial-intake-hub')),
      findsOneWidget,
    );
    expect(find.text('Plan dependable coordination'), findsOneWidget);
    expect(find.text('Quote'), findsOneWidget);
    expect(find.text('Pre-interest registration'), findsOneWidget);
    expect(find.text('Enterprise application'), findsOneWidget);
    expect(find.text('Support and contract boundary'), findsOneWidget);
  });

  testWidgets('commercial action is available from the lifecycle console', (
    tester,
  ) async {
    await tester.pumpWidget(const FiduciaApp(linkStream: Stream<String>.empty()));
    await tester.pump();

    expect(find.text('Fiducia lifecycle console'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fiducia-commercial-intake')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('fiducia-commercial-intake')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fiducia commercial intake'), findsOneWidget);
    expect(find.text('Plan dependable coordination'), findsOneWidget);
  });

  testWidgets('customer journeys expose their non-binding boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CommercialIntakeHub()),
    );

    await tester.tap(find.text('Quote'));
    await tester.pumpAndSettle();
    expect(find.text('Request a quote'), findsOneWidget);
    expect(find.textContaining('non-binding'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('submit-fiducia-quote')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-interest registration'));
    await tester.pumpAndSettle();
    expect(find.text('Register pre-interest'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('submit-fiducia-pre-interest')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enterprise application'));
    await tester.pumpAndSettle();
    expect(find.text('Enterprise application'), findsOneWidget);
    expect(find.textContaining('not itself a contract'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('submit-fiducia-enterprise-application'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('support page distinguishes SLOs from contractual SLAs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SupportAndContractPage()),
    );

    expect(find.text('Engineering SLO'), findsOneWidget);
    expect(find.text('Contractual SLA'), findsOneWidget);
    expect(find.text('Support model'), findsOneWidget);
    expect(find.text('B2B documents'), findsOneWidget);
    expect(find.text('Human review'), findsOneWidget);
  });
}
