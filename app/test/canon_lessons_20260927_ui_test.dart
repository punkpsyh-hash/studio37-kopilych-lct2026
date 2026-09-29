import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/canon_lesson_page.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/ui.dart';

void main() {
  CanonLessonReceipt submit(GameState live, CanonLessonSubmission command) {
    final before = CanonLessonSnapshot(live);
    final alreadyCompleted = live.completed.contains(
      canonLessonMarker(command.lessonId, command.snapshotDay),
    );
    final reward = command.apply(live);
    return CanonLessonReceipt(
      submission: command,
      reward: reward,
      applied: !alreadyCompleted && !command.practice,
      before: before,
      after: live,
    );
  }

  Future<void> pumpLesson(
    WidgetTester tester,
    GameState live,
    String id, {
    double textScale = 1,
    Future<CanonLessonReceipt> Function(CanonLessonSubmission)? onSubmit,
    void Function(String)? onGo,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: CanonLessonPage(
            lessonId: id,
            state: live,
            onSubmit: onSubmit ?? (command) async => submit(live, command),
            onGo: onGo,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder.hitTestable());
    await tester.pump();
  }

  testWidgets('B02 exposes overflow at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState();
    await pumpLesson(tester, state, 'B02', textScale: 1.6);

    await tester.enterText(find.byKey(const Key('B02-care')), '70');
    await tester.enterText(find.byKey(const Key('B02-wants')), '20');
    await tester.enterText(find.byKey(const Key('B02-savings')), '20');
    await tester.pump();

    expect(find.textContaining('Превышение: 10 монет'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(state.planConfirmed, isFalse);
  });

  testWidgets('P01 retries a wrong basket without penalty then earns once', (
    tester,
  ) async {
    final state = GameState()..confirmPlan([15, 10, 15]);
    await pumpLesson(tester, state, 'P01');

    await tapVisible(tester, find.byType(CheckboxListTile).at(0));
    await tapVisible(tester, find.byType(CheckboxListTile).at(2));
    await tapVisible(tester, find.text('Эти упаковки самые яркие'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));

    expect(find.textContaining('Пока не получилось'), findsOneWidget);
    expect(state.wallet, [100, 0, 0]);
    expect(state.completed, isNot(contains('canon:P01:1')));

    await tapVisible(tester, find.byType(CheckboxListTile).at(1));
    await tapVisible(tester, find.byType(CheckboxListTile).at(2));
    await tapVisible(tester, find.text('Корм и чистота нужны питомцу сегодня'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Задание выполнено: +30 монет'), findsOneWidget);
    expect(state.wallet, [130, 0, 0]);
    expect(state.purchased, isEmpty);
    expect(state.completed, contains('canon:P01:1'));
  });

  testWidgets('P01 clearly shows when the period income is already used', (
    tester,
  ) async {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final job = householdJobForPeriod(state.day);
    state.setCurrentRoom(job.room);
    expect(state.finishJob(job.id, period: state.day), 30);
    final walletAfterJob = List<int>.from(state.wallet);
    await pumpLesson(tester, state, 'P01');

    expect(find.text('ДОХОД УЖЕ ПОЛУЧЕН · ЗАДАНИЕ БЕЗ МОНЕТ'), findsOneWidget);
    expect(
      find.textContaining('задание завершится без новых монет'),
      findsOneWidget,
    );

    await tapVisible(tester, find.byType(CheckboxListTile).at(0));
    await tapVisible(tester, find.byType(CheckboxListTile).at(1));
    await tapVisible(tester, find.text('Корм и чистота нужны питомцу сегодня'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Решение сохранено'), findsOneWidget);
    expect(state.wallet, walletAfterJob);
    expect(state.completed, contains('canon:P01:1'));
  });

  testWidgets('S01 compares every goal and keeps savings visible', (
    tester,
  ) async {
    final state = GameState()..wallet = [20, 70, 10];
    await pumpLesson(tester, state, 'S01');

    expect(find.text('Уютный домик'), findsOneWidget);
    expect(find.text('Маленький сад'), findsOneWidget);
    expect(find.text('Звёздный светильник'), findsOneWidget);
    expect(find.text('Накопления после выбора: 70 монет'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('goal-stars')));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(state.goalId, 'stars');
    expect(state.wallet, [20, 70, 10]);
  });

  testWidgets('S02 previews both local outcomes before a real transfer', (
    tester,
  ) async {
    final state = GameState()..wallet = [30, 20, 10];
    await pumpLesson(tester, state, 'S02');

    expect(find.text('УЧЕБНАЯ КОПИЯ · ОБА ВАРИАНТА'), findsOneWidget);
    expect(find.text('В мечту: 20 → 25'), findsOneWidget);
    expect(find.text('В запас: 10 → 15'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('target-reserve')));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(state.wallet, [25, 20, 15]);
    expect(state.completed, contains('canon:S02:1'));
    expect(
      find.text('Переведено 5 монет из «Сейчас» в «Запас».'),
      findsOneWidget,
    );
    expect(find.text('«Сейчас»: 30 → 25 (−5)'), findsOneWidget);
    expect(find.text('«На мечту»: 20 → 20 (0)'), findsOneWidget);
    expect(find.text('«Запас»: 10 → 15 (+5)'), findsOneWidget);
    expect(find.text('Всего: 60 → 60 монет.'), findsOneWidget);
    expect(
      find.text('Сытость, радость и чистота от перевода не изменились.'),
      findsOneWidget,
    );
  });

  testWidgets('P06 labels the rich-wallet shortage as a teaching copy', (
    tester,
  ) async {
    final state = GameState();
    final before = List<int>.from(state.wallet);
    await pumpLesson(tester, state, 'P06');

    expect(find.text('УЧЕБНАЯ КОПИЯ'), findsOneWidget);
    expect(find.textContaining('30 монет против цены 35'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('p06-attempt')));
    expect(
      find.text('Покупка не прошла: не хватает 5 монет. Списано 0.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Отложить лежанку'));
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(state.wallet, before);
    expect(state.purchased, isEmpty);
    expect(state.completed, contains('canon:P06:1'));
  });

  testWidgets('same-period replay is visibly local and does not mutate', (
    tester,
  ) async {
    final state = GameState()..wallet = [30, 20, 10];
    state.completed.addAll(['S02', canonLessonMarker('S02', state.day)]);
    final before = state.toJson();
    await pumpLesson(tester, state, 'S02');

    expect(find.text('ТРЕНИРОВКА · КОШЕЛЁК НЕ МЕНЯЕТСЯ'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();

    expect(state.toJson(), before);
    expect(
      find.text(
        'Учебный перевод проверен. Из основных конвертов списано 0 монет.',
      ),
      findsOneWidget,
    );
    expect(find.text('«Сейчас»: 30 → 30 (0)'), findsOneWidget);
    expect(find.text('«На мечту»: 20 → 20 (0)'), findsOneWidget);
    expect(find.text('«Запас»: 10 → 10 (0)'), findsOneWidget);
    expect(
      find.textContaining('учебная копия', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('S02 receipt waits for save and retains the accepted target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState()..wallet = [30, 20, 10];
    final pending = Completer<CanonLessonReceipt>();
    late CanonLessonSubmission accepted;
    await pumpLesson(
      tester,
      state,
      'S02',
      textScale: 1.6,
      onSubmit: (command) {
        accepted = command;
        return pending.future;
      },
    );
    await tester.enterText(find.byKey(const Key('S02-amount')), '7');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    expect(find.byKey(const Key('canon-transfer-receipt')), findsNothing);
    expect(find.text('Решение сохранено'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('target-reserve')));
    final receipt = submit(state, accepted);
    pending.complete(receipt);
    await tester.pumpAndSettle();
    expect(
      find.text('Переведено 7 монет из «Сейчас» в «На мечту».'),
      findsOneWidget,
    );
    expect(find.text('«Сейчас»: 30 → 23 (−7)'), findsOneWidget);
    expect(find.text('«На мечту»: 20 → 27 (+7)'), findsOneWidget);
    expect(find.text('«Запас»: 10 → 10 (0)'), findsOneWidget);
    expect(state.wallet, [23, 27, 10]);
    expect(() => receipt.after.wallet[0] = 0, throwsUnsupportedError);
    expect(() => receipt.before.needs[0] = 0, throwsUnsupportedError);
    state.wallet[0] = 99;
    await tester.pump();
    expect(find.text('«Сейчас»: 30 → 23 (−7)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S02 duplicate reports current unchanged values instead of a stale transfer',
    (tester) async {
      final state = GameState()..wallet = [30, 20, 10];
      await pumpLesson(tester, state, 'S02');
      // Another submission completed while this page was open. The domain accepts
      // the retry before validating the now stale opening snapshot.
      state.completed.addAll(['S02', canonLessonMarker('S02', state.day)]);
      state.wallet = [77, 66, 55];
      await tapVisible(tester, find.byKey(const Key('canon-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Это задание уже выполнено. Новый перевод не выполнялся: списано 0 монет.',
        ),
        findsOneWidget,
      );
      expect(find.text('«Сейчас»: 77 → 77 (0)'), findsOneWidget);
      expect(find.text('«На мечту»: 66 → 66 (0)'), findsOneWidget);
      expect(find.text('«Запас»: 55 → 55 (0)'), findsOneWidget);
      expect(find.text('Всего: 198 → 198 монет.'), findsOneWidget);
      expect(find.textContaining('Переведено 5 монет'), findsNothing);
      expect(state.wallet, [77, 66, 55]);
    },
  );

  testWidgets('S02 stale rejection has no success receipt or next action', (
    tester,
  ) async {
    final state = GameState()..wallet = [30, 20, 10];
    await pumpLesson(
      tester,
      state,
      'S02',
      onGo: (_) => fail('No route on failure'),
    );
    state.wallet = [29, 21, 10];
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Баланс уже изменился'), findsOneWidget);
    expect(find.byKey(const Key('canon-transfer-receipt')), findsNothing);
    expect(find.text('Решение сохранено'), findsNothing);
    expect(find.text('Открыть бюджет'), findsNothing);
    expect(state.wallet, [29, 21, 10]);
    expect(state.completed, isEmpty);
  });

  testWidgets('S01 next step uses the confirmed result without a plan', (
    tester,
  ) async {
    final state = GameState()..name = 'Пушок';
    String? route;
    await pumpLesson(tester, state, 'S01', onGo: (target) => route = target);
    await tapVisible(tester, find.byKey(const Key('canon-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Составить исходный план'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('canon-next-step')));
    expect(route, 'B02');
    expect(state.wallet, [100, 0, 0]);
  });

  testWidgets(
    'S01 next step follows the saved story even when the opening plan is stale',
    (tester) async {
      final state = GameState()..name = 'Пушок';
      String? route;
      await pumpLesson(tester, state, 'S01', onGo: (target) => route = target);
      state.confirmPlan([15, 35, 50]);
      state.completed.addAll(['B02', canonLessonMarker('B02', state.day)]);
      await tapVisible(tester, find.byKey(const Key('goal-stars')));
      await tapVisible(tester, find.byKey(const Key('canon-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Собрать учебную корзину необходимого'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('canon-next-step')));
      expect(route, 'P01');
      expect(state.goalId, 'stars');
      expect(state.wallet, [100, 0, 0]);
    },
  );
}
