import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/mission_page.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> openMissions(WidgetTester tester) async {
  tester
      .widget<NavigationBar>(find.byType(NavigationBar))
      .onDestinationSelected!(2);
  await tester.pump();
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    2,
  );
  await tester.pumpAndSettle();
  await tester.drag(find.byType(ListView).last, const Offset(0, 10000));
  await tester.pumpAndSettle();
  expect(find.text('Учимся на маленьком'), findsOneWidget);
}

void main() {
  final lesson = missions.firstWhere((mission) => mission.kind != 'action');
  final goalLesson = canonicalMissions.firstWhere(
    (mission) => mission.id == 'S01',
  );

  for (final claimSource in ['none', 'dishes', 'lesson']) {
    testWidgets('Mission entries use shared period income after $claimSource', (
      tester,
    ) async {
      sqfliteFfiInit();
      final store = await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      );
      final state = GameState()
        ..name = 'Листик'
        ..reducedMotion = true
        ..currentRoom = 'kitchen';
      state.confirmPlan([20, 0, 10]);
      if (claimSource == 'dishes') {
        state.finishDishJob(period: state.day);
      } else if (claimSource == 'lesson') {
        state.finish(
          lesson,
          lesson.correct,
          DateTime(2026, 9, 25),
          withoutHint: true,
        );
      }
      final controller = GameController(store!)..state = state;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await store.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller, useMeshyModels: false),
        ),
      );

      final expected = claimSource == 'none'
          ? 'Награда: 30 монет'
          : 'Тренировка · без монет';
      await tester.scrollUntilVisible(
        find.text(goalLesson.title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(goalLesson.title), findsOneWidget);
      expect(find.text('Без награды'), findsOneWidget);
      expect(
        find.text('Награда: 30 монет'),
        findsNothing,
        reason: 'The current S01 goal choice is a real action without income.',
      );
      expect(state.total, claimSource == 'none' ? 100 : 130);

      await openMissions(tester);
      expect(find.textContaining(expected), findsWidgets);
      if (claimSource != 'none') {
        expect(find.textContaining('+30 монет'), findsNothing);
      }
    });
  }

  testWidgets(
    'A paid once lesson stays training when the new day income is available',
    (tester) async {
      sqfliteFfiInit();
      final store = await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      );
      final onceLesson = missions.firstWhere(
        (mission) => mission.period == 'once' && mission.kind != 'action',
      );
      final dailyLesson = missions.firstWhere(
        (mission) => mission.period == 'daily' && mission.kind != 'action',
      );
      final state = GameState()
        ..name = 'Листик'
        ..reducedMotion = true;
      state.confirmPlan([20, 0, 10]);
      state.finish(
        onceLesson,
        onceLesson.correct,
        DateTime(2026, 9, 25),
        withoutHint: true,
      );
      state.endDay();
      state.confirmPlan([20, 0, 10]);
      expect(state.incomeAvailable, isTrue);

      final controller = GameController(store!)..state = state;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await store.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller, useMeshyModels: false),
        ),
      );

      await tester.scrollUntilVisible(
        find.text(goalLesson.title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(goalLesson.title), findsOneWidget);
      expect(find.text('Награда: 30 монет'), findsNothing);
      expect(state.incomeAvailable, isTrue);

      await openMissions(tester);
      await tester.scrollUntilVisible(
        find.text(onceLesson.title),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(onceLesson.title));
      await tester.pumpAndSettle();
      expect(find.textContaining('ТРЕНИРОВКА · БЕЗ МОНЕТ'), findsOneWidget);
      await tester.tap(find.text(onceLesson.options[onceLesson.correct]));
      await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
      await tester.tap(find.text('Проверить решение'));
      await tester.pumpAndSettle();
      expect(find.text('Тренировка завершена'), findsOneWidget);
      expect(state.wallet, [130, 0, 0]);
      expect(state.incomeAvailable, isTrue);

      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(dailyLesson.title),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text(dailyLesson.title));
      await tester.pumpAndSettle();
      expect(find.text(dailyLesson.title).hitTestable(), findsOneWidget);
      await tester.tap(find.text(dailyLesson.title).hitTestable());
      await tester.pumpAndSettle();
      expect(find.textContaining('НАГРАДА: 30 МОНЕТ'), findsOneWidget);
    },
  );

  test('a once lesson cannot consume the next period income slot', () {
    final onceLesson = missions.firstWhere(
      (mission) => mission.period == 'once' && mission.kind != 'action',
    );
    final dailyLesson = missions.firstWhere(
      (mission) => mission.period == 'daily' && mission.kind != 'action',
    );
    final now = DateTime(2026, 9, 27);
    final state = GameState()..confirmPlan([15, 0, 10]);
    expect(
      state.finish(onceLesson, onceLesson.correct, now, withoutHint: true),
      30,
    );
    state.endDay();
    state.confirmPlan([15, 0, 10]);
    final beforeReplay = jsonEncode(state.toJson());

    expect(
      state.finish(onceLesson, onceLesson.correct, now, withoutHint: true),
      0,
    );
    expect(jsonEncode(state.toJson()), beforeReplay);
    expect(state.wallet, [130, 0, 0]);
    expect(state.incomeAvailable, isTrue);
    expect(
      state.finish(dailyLesson, dailyLesson.correct, now, withoutHint: true),
      30,
    );
    expect(state.wallet, [160, 0, 0]);
    expect(state.incomeAvailable, isFalse);
    state.setCurrentRoom('kitchen');
    expect(state.finishDishJob(period: state.day), 0);
    expect(state.wallet, [160, 0, 0]);
  });

  for (final oldKey in ['M01:once', 'M01:period:1']) {
    test('completed once lessons remain practice with saved key $oldKey', () {
      final state = GameState()
        ..day = 2
        ..wallet = [130, 0, 0]
        ..completed.add(lesson.id)
        ..rewards.add(oldKey);
      state.confirmPlan([15, 0, 10]);
      final restored = GameState.fromJson(state.toJson());
      final beforeReplay = jsonEncode(restored.toJson());
      final now = DateTime(2026, 10, 10);

      expect(restored.rewardClaimed(lesson, now), isTrue);
      expect(
        restored.finish(lesson, lesson.correct, now, withoutHint: true),
        0,
      );
      expect(jsonEncode(restored.toJson()), beforeReplay);
      expect(restored.incomeAvailable, isTrue);
    });
  }

  for (final (practice, compact) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      '3D home distinguishes no-reward action from replay $practice compact $compact',
      (tester) async {
        tester.view.physicalSize = compact
            ? const Size(360, 800)
            : const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: GameHome(
                state: GameState()..name = 'Персик',
                scene: const ColoredBox(color: Colors.white),
                ready: true,
                busy: false,
                lessonIncomeAvailable: false,
                lessonWithoutReward: !practice,
                onRoom: (_) {},
                onCare: () {},
                onLamp: () {},
                onPlan: () {},
                onMission: () {},
                onDream: () {},
                onNextDay: () {},
              ),
            ),
          ),
        );
        final button = find.byKey(const ValueKey('scene-mission'));
        if (compact) {
          expect(
            find.descendant(
              of: button,
              matching: find.text(practice ? 'Без монет' : 'Без награды'),
            ),
            findsOneWidget,
          );
          final semantics = find.ancestor(
            of: button,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label ==
                      (practice
                          ? 'Задание. Тренировка · без монет'
                          : 'Задание. Без награды'),
            ),
          );
          expect(semantics, findsOneWidget);
        } else {
          // The redesigned HUD uses the same labelled dock button in both
          // layouts: title plus a short reward detail.
          expect(
            find.descendant(
              of: button,
              matching: find.text(practice ? 'Без монет' : 'Без награды'),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Mission explains reward source and that a plan is not a transfer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MissionPage(
            mission: lesson,
            practice: false,
            incomeAvailable: true,
            onComplete: (_, _) async => 30,
          ),
        ),
      );

      expect(find.textContaining('НАГРАДА: 30 МОНЕТ'), findsOneWidget);
      await tester.tap(find.text(lesson.options[lesson.correct]));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
      await tester.tap(find.text('Проверить решение'));
      await tester.pumpAndSettle();

      expect(find.text('От родителей за помощь: +30 монет'), findsOneWidget);
      expect(
        find.textContaining('сам план не переводит монеты между конвертами'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Mission announces no coins before a new lesson after shared claim',
    (tester) async {
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MissionPage(
            mission: lesson,
            practice: false,
            incomeAvailable: false,
            onComplete: (_, _) async {
              completions++;
              return 0;
            },
          ),
        ),
      );

      expect(find.textContaining('ТРЕНИРОВКА · БЕЗ МОНЕТ'), findsOneWidget);
      expect(find.text('Тренировка'), findsOneWidget);
      await tester.tap(find.text(lesson.options[lesson.correct]));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
      await tester.tap(find.text('Проверить решение'));
      await tester.pumpAndSettle();
      expect(completions, 1, reason: 'A new lesson still records its progress');
      expect(find.text('Тренировка завершена'), findsOneWidget);
    },
  );

  testWidgets('Repeated action promises no new income before confirmation', (
    tester,
  ) async {
    final action = missions.firstWhere((mission) => mission.kind == 'action');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MissionPage(
          mission: action,
          practice: true,
          incomeAvailable: true,
          onComplete: (_, _) async => 0,
        ),
      ),
    );

    expect(
      find.text(
        'Тренировка · без монет. Действие можно повторить, но новый доход не появится.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Награда дастся'), findsNothing);
  });
}
