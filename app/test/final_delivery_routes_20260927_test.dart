import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/canon_lesson_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> settleController(
  WidgetTester tester,
  GameController controller,
) async {
  for (var attempt = 0; attempt < 100 && controller.busy; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(controller.busy, isFalse, reason: 'SQLite save must complete');
  await tester.pump(const Duration(milliseconds: 500));
}

CanonLessonReceipt applyLesson(
  GameState state,
  CanonLessonSubmission submission,
) {
  final before = CanonLessonSnapshot(state);
  final alreadyCompleted = state.completed.contains(
    canonLessonMarker(submission.lessonId, submission.snapshotDay),
  );
  final reward = submission.apply(state);
  return CanonLessonReceipt(
    submission: submission,
    reward: reward,
    applied: !alreadyCompleted && !submission.practice,
    before: before,
    after: state,
  );
}

void main() {
  testWidgets(
    'B04 widget records an explained revision and keeps its baseline',
    (tester) async {
      final state = GameState()..confirmPlan([15, 10, 15]);
      final job = householdJobForPeriod(state.day);
      state.setCurrentRoom(job.room);
      expect(state.finishJob(job.id, period: state.day), 30);

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: CanonLessonPage(
            lessonId: 'B04',
            state: state,
            onSubmit: (submission) async => applyLesson(state, submission),
          ),
        ),
      );

      expect(
        find.text('Исходный план: забота 15, желания 10, накопления 15.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('B04-wants')), '0');
      await tester.enterText(find.byKey(const Key('B04-savings')), '25');
      await tapVisible(tester, find.text('После дохода уточняю суммы'));
      await tapVisible(tester, find.byKey(const Key('canon-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Решение сохранено'), findsOneWidget);
      expect(
        find.text('Новая версия добавлена, а исходный план остался в истории.'),
        findsOneWidget,
      );
      expect(state.planVersions.map((version) => version.split), [
        [15, 10, 15],
        [15, 0, 25],
      ]);
      expect(state.planVersions.last.reason, 'После дохода уточняю суммы');
      expect(state.wallet, [130, 0, 0]);
    },
  );

  testWidgets('production task routes persist B04 and P06 without spending', (
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
    await tester.runAsync(() async {
      await controller.load();
      await controller.change('Production route prerequisites', (state) {
        state.name = 'Пушок';
        state.confirmPlan([15, 10, 15]);
        final job = householdJobForPeriod(state.day);
        state.setCurrentRoom(job.room);
        expect(state.finishJob(job.id, period: state.day), 30);
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Задания'));
    await tester.pump(const Duration(milliseconds: 500));

    final b04 = find.text('План можно изменить');
    await tester.scrollUntilVisible(
      b04,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tapVisible(tester, b04);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('B04-wants')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('B04-wants')), '0');
    await tester.enterText(find.byKey(const Key('B04-savings')), '25');
    await tapVisible(tester, find.text('После дохода уточняю суммы'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await settleController(tester, controller);
    expect(find.text('Решение сохранено'), findsOneWidget);
    expect(controller.state!.planVersions, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Задания'));
    await tester.pump(const Duration(milliseconds: 500));
    final p06Text = find.text('Хочу, но пока не хватает');
    for (var attempt = 0;
        attempt < 8 && p06Text.evaluate().isEmpty;
        attempt++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final p06 = p06Text.first;
    expect(p06, findsOneWidget);
    await tapVisible(tester, p06);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('p06-attempt')), findsOneWidget);
    final walletBeforeP06 = List<int>.of(controller.state!.wallet);
    await tapVisible(tester, find.byKey(const Key('p06-attempt')));
    await tapVisible(tester, find.text('Отложить лежанку'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await settleController(tester, controller);

    expect(find.text('Решение сохранено'), findsOneWidget);
    expect(controller.state!.completed, contains('canon:P06:1'));
    expect(controller.state!.wallet, walletBeforeP06);
    expect(controller.state!.purchased, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
