import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/adult_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> confirmAndSave(
  WidgetTester tester,
  GameController controller,
) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Подтвердить'));
  await tester.pumpAndSettle();
  // SQLite completes on the real event loop, while controller notifications
  // and route futures also need the widget test's fake microtask queue pumped.
  for (var attempt = 0; attempt < 100 && controller.busy; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    controller.busy,
    isFalse,
    reason: 'SQLite profile switch must complete',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adult gate switches and resets only the separate test profile', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = GameController(store);
    await tester.runAsync(() async {
      await controller.load();
      await controller.change('Основной профиль для проверки', (state) {
        state.name = 'Листик';
        state.wallet = [73, 21, 6];
        state.reducedMotion = true;
      });
    });
    final primary = jsonEncode(controller.state!.toJson());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AdultGate(controller: controller),
      ),
    );
    expect(find.text('Открыть демопрофиль'), findsNothing);
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Попробуй ещё раз'), findsOneWidget);
    final question = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .labelText!;
    final numbers = RegExp(
      r'\d+',
    ).allMatches(question).map((m) => int.parse(m.group(0)!)).toList();
    await tester.enterText(
      find.byType(TextField),
      '${numbers[0] + numbers[1]}',
    );
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('adult-quick-check-start'));
    await tester.scrollUntilVisible(start, 240);
    await tester.pumpAndSettle();
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(jsonEncode(controller.state!.toJson()), primary);
    await tester.tap(start);
    await confirmAndSave(tester, controller);
    expect(controller.state!.demoMode, isTrue);
    expect(controller.state!.day, 1);
    expect(controller.state!.wallet, [100, 0, 0]);
    expect(controller.state!.facts, isEmpty);

    // A successful quick-check action closes the adult route. Reopen it to
    // exercise the remaining controls in this isolated widget test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AdultPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => controller.change('Тестовое действие', (state) {
        state.confirmPlan([15, 0, 10]);
        state.transfer(0, 1, 10);
      }),
    );
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('adult-quick-check-reset'));
    await tester.scrollUntilVisible(reset, 160);
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await confirmAndSave(tester, controller);
    expect(controller.state!.wallet, [100, 0, 0]);
    expect(controller.state!.facts, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AdultPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final exit = find.text('Вернуться в основной профиль');
    await tester.scrollUntilVisible(exit, -160);
    await tester.pumpAndSettle();
    await tester.ensureVisible(exit);
    await tester.pumpAndSettle();
    await tester.tap(exit);
    await confirmAndSave(tester, controller);
    expect(jsonEncode(controller.state!.toJson()), primary);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(store.close);
  });
}
