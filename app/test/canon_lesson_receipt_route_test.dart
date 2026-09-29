import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/canon_lesson_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder.hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
  }) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (condition()) return;
    }
    fail(reason ?? 'Timed out waiting for the persisted UI state.');
  }

  Future<void> openCanonicalLesson(WidgetTester tester, String title) async {
    await tapVisible(tester, find.text('Задания'));
    await tester.scrollUntilVisible(
      find.text(title),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tapVisible(tester, find.text(title));
    expect(find.byType(CanonLessonPage), findsOneWidget);
  }

  testWidgets(
    'S02 production route publishes its receipt only after SQLite commit',
    (tester) async {
      final openedStore = await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      );
      final store = openedStore!;
      await tester.runAsync(
        () => store.change('seed-s02', 'Подготовка S02', (state) {
          state
            ..name = 'Листик'
            ..reducedMotion = true;
          state.confirmPlan([15, 10, 15]);
        }),
      );
      final initialState = await tester.runAsync(store.load);
      final controller = GameController(store)..state = initialState!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(store.close);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller, useMeshyModels: false),
        ),
      );
      await tester.pumpAndSettle();
      await openCanonicalLesson(tester, 'Мечта и запас');

      final databaseBefore = await tester.runAsync(() async {
        final saved = await store.load();
        return (
          saved: jsonEncode(saved.toJson()),
          operations: await store.history(),
          finance: await store.financialHistory(),
          rawEvents: await store.db.query('operation_events'),
        );
      });
      final before = databaseBefore!;
      final savedBefore = before.saved;
      final controllerBefore = jsonEncode(controller.state!.toJson());
      final operationsBefore = before.operations;
      final eventsBefore = before.finance;
      final rawEventsBefore = before.rawEvents;
      await tester.runAsync(
        () => store.db.execute(
          "CREATE TRIGGER fail_canon_receipt BEFORE UPDATE ON state "
          "BEGIN SELECT RAISE(ABORT, 'simulated receipt failure'); END",
        ),
      );

      await tapVisible(tester, find.byKey(const Key('canon-submit')));
      await waitFor(
        tester,
        () =>
            !controller.busy &&
            find
                .text('Не удалось сохранить действие. Попробуй ещё раз.')
                .evaluate()
                .isNotEmpty,
        reason: 'The failed transaction did not return control to the lesson.',
      );

      expect(
        find.text('Не удалось сохранить действие. Попробуй ещё раз.'),
        findsOneWidget,
      );
      expect(find.text('Решение сохранено'), findsNothing);
      expect(find.byKey(const Key('canon-transfer-receipt')), findsNothing);
      expect(find.text('Открыть бюджет'), findsNothing);
      final databaseAfterFailure = await tester.runAsync(() async {
        final saved = await store.load();
        return (
          saved: jsonEncode(saved.toJson()),
          operations: await store.history(),
          finance: await store.financialHistory(),
          rawEvents: await store.db.query('operation_events'),
        );
      });
      final afterFailure = databaseAfterFailure!;
      expect(afterFailure.saved, savedBefore);
      expect(jsonEncode(controller.state!.toJson()), controllerBefore);
      expect(afterFailure.operations, operationsBefore);
      expect(afterFailure.finance, eventsBefore);
      expect(afterFailure.rawEvents, rawEventsBefore);

      await tester.runAsync(
        () => store.db.execute('DROP TRIGGER fail_canon_receipt'),
      );
      await tapVisible(tester, find.byKey(const Key('canon-submit')));
      await waitFor(
        tester,
        () =>
            !controller.busy &&
            find
                .byKey(const Key('canon-transfer-receipt'))
                .evaluate()
                .isNotEmpty,
        reason: 'The committed transfer receipt did not appear.',
      );

      expect(find.text('Решение сохранено'), findsOneWidget);
      expect(find.byKey(const Key('canon-transfer-receipt')), findsOneWidget);
      expect(
        find.text('Переведено 5 монет из «Сейчас» в «На мечту».'),
        findsOneWidget,
      );
      expect(find.text('«Сейчас»: 100 → 95 (−5)'), findsOneWidget);
      expect(find.text('«На мечту»: 0 → 5 (+5)'), findsOneWidget);
      expect(find.text('Всего: 100 → 100 монет.'), findsOneWidget);
      expect(find.text('Открыть бюджет'), findsOneWidget);

      final databaseAfterSuccess = await tester.runAsync(() async {
        return (
          saved: await store.load(),
          operations: await store.history(),
          finance: await store.financialHistory(),
          rawEvents: await store.db.query('operation_events'),
        );
      });
      final afterSuccess = databaseAfterSuccess!;
      final savedAfter = afterSuccess.saved;
      expect(savedAfter.wallet, [95, 5, 0]);
      expect(savedAfter.completed, contains(canonLessonMarker('S02', 1)));
      final operationsAfter = afterSuccess.operations;
      expect(operationsAfter, hasLength(operationsBefore.length + 1));
      expect(operationsAfter.first['label'], 'Задание: Мечта и запас');
      expect(operationsAfter.first['delta'], 0);
      final eventsAfter = afterSuccess.finance;
      expect(eventsAfter, hasLength(eventsBefore.length + 1));
      expect(eventsAfter.first['kind'], 'transfer');
      expect(eventsAfter.first['category'], 'savings');
      expect(eventsAfter.first['amount'], 5);
      expect(eventsAfter.first['from_wallet'], 0);
      expect(eventsAfter.first['to_wallet'], 1);
      expect(eventsAfter.first['period'], 1);
      expect(afterSuccess.rawEvents, hasLength(rawEventsBefore.length + 1));
      expect(
        afterSuccess.rawEvents.where(
          (row) => row['operation_id'] == eventsAfter.first['operation_id'],
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S01 receipt CTA follows the production route to B02', (
    tester,
  ) async {
    final openedStore = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    final store = openedStore!;
    await tester.runAsync(
      () => store.change('seed-s01', 'Подготовка S01', (state) {
        state
          ..name = 'Листик'
          ..reducedMotion = true;
      }),
    );
    final initialState = await tester.runAsync(store.load);
    final controller = GameController(store)..state = initialState!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(store.close);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );
    await tester.pumpAndSettle();
    await openCanonicalLesson(tester, 'Выбираем мечту');
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await waitFor(
      tester,
      () =>
          !controller.busy &&
          find.byKey(const Key('canon-next-step')).evaluate().isNotEmpty,
      reason: 'The committed S01 receipt CTA did not appear.',
    );

    expect(find.text('Решение сохранено'), findsOneWidget);
    expect(find.byKey(const Key('canon-next-step')), findsOneWidget);
    expect(find.text('Составить исходный план'), findsOneWidget);
    expect(controller.state!.planConfirmed, isFalse);
    expect(controller.state!.completed, contains(canonLessonMarker('S01', 1)));

    await tapVisible(tester, find.byKey(const Key('canon-next-step')));

    expect(find.byType(CanonLessonPage), findsOneWidget);
    expect(find.text('Три направления плана'), findsWidgets);
    expect(find.byKey(const Key('B02-care')), findsOneWidget);
    expect(find.byKey(const Key('B02-wants')), findsOneWidget);
    expect(find.byKey(const Key('B02-savings')), findsOneWidget);
    final persisted = await tester.runAsync(store.load);
    expect(persisted!.planConfirmed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
