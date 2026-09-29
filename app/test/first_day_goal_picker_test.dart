import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('first dream is chosen from pictured prices and saved once', (
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
    addTearDown(() async {
      controller.dispose();
      await tester.runAsync(store.close);
    });
    await tester.runAsync(controller.load);
    await tester.runAsync(
      () => controller.change('First day ready for a goal', (state) {
        state.name = 'Плюш';
        state.completed.addAll({
          'intro-started',
          'canon:B02:1',
          'intro-toy-play',
          'intro-money',
        });
        state.care(1);
        state.confirmPlan([20, 0, 10]);
        state.care(0);
        state.care(2);
        state.buyItem(catalogItems.singleWhere((item) => item.id == 'ball'));
      }),
    );
    final before = List<int>.of(controller.state!.wallet);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('История').last);
    await tester.pump(const Duration(milliseconds: 500));
    final step = find.widgetWithText(
      FilledButton,
      'Большая покупка дороже. Выберем мечту и будем копить!',
    );
    await tester.ensureVisible(step);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(step);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Маленький сад'), findsWidgets);
    expect(find.text('Уютный домик'), findsWidgets);
    expect(find.text('Звёздный светильник'), findsWidgets);
    expect(find.text('100'), findsWidgets);
    expect(find.text('120'), findsWidgets);
    expect(find.text('150'), findsWidgets);

    final garden = find.byKey(const ValueKey('intro-goal-garden'));
    await tester.ensureVisible(garden);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(garden);
    for (var i = 0; i < 50 && controller.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.state!.goalId, 'garden');
    expect(controller.state!.completed, contains(canonLessonMarker('S01', 1)));
    expect(controller.state!.wallet, before);
    final persisted = await tester.runAsync(store.load);
    expect(persisted!.goalId, 'garden');
  });
}
