import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<GameController> controllerFor(WidgetTester tester) async {
  sqfliteFfiInit();
  final store = (await tester.runAsync(
    () =>
        GameStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi),
  ))!;
  final controller = GameController(store);
  addTearDown(() async {
    controller.dispose();
    await tester.runAsync(store.close);
  });
  await tester.runAsync(controller.load);
  await tester.runAsync(
    () => controller.change('Choose pet', (state) {
      state.name = 'Пушок';
    }),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: GameShell(controller: controller, useMeshyModels: false),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return controller;
}

Future<void> tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(finder.hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> saved(WidgetTester tester, GameController controller) async {
  for (var i = 0; i < 100 && controller.busy; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(controller.busy, isFalse);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> openTask(WidgetTester tester, String title) async {
  await tapShown(tester, find.text('Задания').last);
  final target = find.text(title);
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tapShown(tester, target);
}

void main() {
  testWidgets(
    'first period reaches S01, B02, P01, B04 and S02 through game UI',
    (tester) async {
      final controller = await controllerFor(tester);
      await tapShown(tester, find.text('История').last);
      await tapShown(
        tester,
        find.widgetWithText(FilledButton, 'Сравнить три мечты и выбрать свою'),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isTrue,
      );
      expect(
        find.byKey(const Key('goal-house')),
        findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .join(' | '),
      );
      await tapShown(tester, find.byKey(const Key('canon-submit')));
      await saved(tester, controller);
      expect(
        controller.state!.completed,
        contains(canonLessonMarker('S01', 1)),
      );
      await tapShown(tester, find.byKey(const Key('canon-next-step')));
      expect(find.byKey(const Key('B02-care')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('B02-care')), '15');
      await tester.enterText(find.byKey(const Key('B02-wants')), '10');
      await tester.enterText(find.byKey(const Key('B02-savings')), '15');
      await tapShown(tester, find.byKey(const Key('canon-submit')));
      await saved(tester, controller);
      expect(
        controller.state!.completed,
        contains(canonLessonMarker('B02', 1)),
      );
      await tapShown(tester, find.byTooltip('Назад'));
      await tapShown(tester, find.text('История').last);
      await tapShown(
        tester,
        find.widgetWithText(
          FilledButton,
          'Собрать учебную корзину необходимого',
        ),
      );
      await tapShown(tester, find.byType(CheckboxListTile).at(0));
      await tapShown(tester, find.byType(CheckboxListTile).at(1));
      await tapShown(tester, find.text('Корм и чистота нужны питомцу сегодня'));
      await tapShown(tester, find.byKey(const Key('canon-submit')));
      await saved(tester, controller);
      expect(
        controller.state!.completed,
        contains(canonLessonMarker('P01', 1)),
      );
      expect(controller.state!.wallet, [130, 0, 0]);
      await tapShown(tester, find.byTooltip('Назад'));
      await tapShown(tester, find.text('История').last);
      await tapShown(
        tester,
        find.widgetWithText(
          FilledButton,
          'После дохода объяснённо уточнить план',
        ),
      );
      await tester.enterText(find.byKey(const Key('B04-wants')), '0');
      await tester.enterText(find.byKey(const Key('B04-savings')), '25');
      await tapShown(tester, find.text('После дохода уточняю суммы'));
      await tapShown(tester, find.byKey(const Key('canon-submit')));
      await saved(tester, controller);
      expect(
        controller.state!.completed,
        contains(canonLessonMarker('B04', 1)),
      );
      expect(controller.state!.planVersions, hasLength(2));
      await tapShown(tester, find.byTooltip('Назад'));
      await openTask(tester, 'Мечта и запас');
      expect(find.byKey(const Key('S02-amount')), findsOneWidget);
      await tapShown(tester, find.byKey(const Key('canon-submit')));
      await saved(tester, controller);
      expect(
        controller.state!.completed,
        contains(canonLessonMarker('S02', 1)),
      );
      expect(controller.state!.wallet, [125, 5, 0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review UI advances five periods and P06 preserves wallet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await controllerFor(tester);
    for (var day = 1; day <= 4; day++) {
      await tester.runAsync(
        () => controller.change('Plan period $day', (state) {
          state.confirmPlan([15, 10, 15]);
        }),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tapShown(tester, find.text('Дом').last);
      final finish = find.text('Завершить день');
      await tester.scrollUntilVisible(
        finish,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(tester.element(finish), alignment: 0.5);
      await tester.pump(const Duration(milliseconds: 500));
      await tapShown(tester, finish);
      expect(find.text('Итоги дня $day'), findsOneWidget);
      if (find.text('Я иначе распределил накопления').evaluate().isNotEmpty) {
        await tapShown(tester, find.text('Я иначе распределил накопления'));
      }
      await tapShown(tester, find.byKey(const Key('finish-reviewed-period')));
      await saved(tester, controller);
      expect(controller.state!.day, day + 1);
      expect(controller.state!.facts, hasLength(day));
    }
    await tester.runAsync(
      () => controller.change('Fifth period plan', (state) {
        state.confirmPlan([15, 10, 15]);
      }),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await openTask(tester, 'Хочу, но пока не хватает');
    final before = List<int>.of(controller.state!.wallet);
    await tapShown(tester, find.byKey(const Key('p06-attempt')));
    await tapShown(tester, find.text('Отложить лежанку'));
    await tapShown(tester, find.byKey(const Key('canon-submit')));
    await saved(tester, controller);
    expect(controller.state!.completed, contains(canonLessonMarker('P06', 5)));
    expect(controller.state!.wallet, before);
    expect(controller.state!.purchased, isEmpty);
    await tapShown(tester, find.byTooltip('Назад'));
    await tapShown(tester, find.text('Дом').last);
    final finish = find.text('Завершить день');
    await tester.scrollUntilVisible(
      finish,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(finish), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 500));
    await tapShown(tester, finish);
    expect(find.text('Итоги дня 5'), findsOneWidget);
    if (find.text('Я иначе распределил накопления').evaluate().isNotEmpty) {
      await tapShown(tester, find.text('Я иначе распределил накопления'));
    }
    await tapShown(tester, find.byKey(const Key('finish-reviewed-period')));
    await saved(tester, controller);
    expect(controller.state!.day, 6);
    expect(controller.state!.facts, hasLength(5));
    expect(tester.takeException(), isNull);
  });
}
