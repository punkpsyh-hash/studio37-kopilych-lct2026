import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper_panel.dart';

void main() {
  testWidgets('floating helper opens and answers offline if model fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Positioned(
                right: 12,
                bottom: 12,
                child: FinanceHelperPanel(
                  loadModel: () async => throw StateError('No model'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('?'));
    await tester.pumpAndSettle();
    expect(find.text('Спросить про деньги'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Что такое бюджет?');
    await tester.tap(find.text('Спросить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Бюджет — план'), findsOneWidget);
  });
}
