import 'package:fiducia_flutter/main.dart';
import 'package:fiducia_flutter/src/commercial/commercial_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    360,
    maxScrolls: 100,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

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

    final supportBoundary = find.text('Support and contract boundary');
    await reveal(tester, supportBoundary);
    expect(supportBoundary, findsOneWidget);
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
    final quoteSubmit = find.byKey(
      const ValueKey<String>('submit-fiducia-quote'),
    );
    await reveal(tester, quoteSubmit);
    expect(quoteSubmit, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-interest registration'));
    await tester.pumpAndSettle();
    expect(find.text('Register pre-interest'), findsOneWidget);
    final preInterestSubmit = find.byKey(
      const ValueKey<String>('submit-fiducia-pre-interest'),
    );
    await reveal(tester, preInterestSubmit);
    expect(preInterestSubmit, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enterprise application'));
    await tester.pumpAndSettle();
    expect(find.text('Enterprise application'), findsOneWidget);
    expect(find.textContaining('not itself a contract'), findsOneWidget);
    final applicationSubmit = find.byKey(
      const ValueKey<String>('submit-fiducia-enterprise-application'),
    );
    await reveal(tester, applicationSubmit);
    expect(applicationSubmit, findsOneWidget);
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

    final humanReview = find.text('Human review');
    await reveal(tester, humanReview);
    expect(humanReview, findsOneWidget);
  });
}
