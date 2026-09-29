import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper_panel.dart';

void main() {
  testWidgets('menu route opens the question form immediately', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceHelperPanel(
            initiallyOpen: true,
            loadModel: () async => throw StateError('No model'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Спросить'), findsOneWidget);
  });

  testWidgets('question survives a keyboard-sized viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceHelperPanel(
            loadModel: () async => throw StateError('No model'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Что такое бюджет?');
    tester.view.physicalSize = const Size(360, 420);
    await tester.pumpAndSettle();
    expect(find.text('Что такое бюджет?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 720), const Size(960, 540)]) {
    testWidgets('helper card fits ${size.width}×${size.height}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 12,
                  top: size.width < size.height ? 300 : 110,
                  child: FinanceHelperPanel(
                    maxCardWidth: 260,
                    maxCardHeight: 220,
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
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
