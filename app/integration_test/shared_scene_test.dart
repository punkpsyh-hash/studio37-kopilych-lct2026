import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kopilych/main.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android shared 3D: rooms, contact, lamp and persisted finance', (
    tester,
  ) async {
    final path =
        '${await getDatabasesPath()}/scene-${DateTime.now().millisecondsSinceEpoch}.db';
    var store = await GameStore.open(path: path);
    await tester.pumpWidget(KopilychApp(store: store));

    Future<void> until(bool Function() condition, String description) async {
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (condition()) return;
      }
      final diagnostic = find.byType(SharedRoom).evaluate().isNotEmpty
          ? tester.state<SharedRoomState>(find.byType(SharedRoom)).diagnostics
          : <String, Object?>{};
      fail('Timed out: $description; scene=$diagnostic');
    }

    Future<void> capture(String label) async {
      await tester.pump(const Duration(seconds: 5));
      debugPrint('SCENE_CAPTURE $label');
      if (const bool.fromEnvironment('CAPTURE_PAUSES')) {
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }

    SharedRoomState scene() =>
        tester.state<SharedRoomState>(find.byType(SharedRoom));
    Finder verticalScroll() => find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;
    await until(
      () => find.byType(SharedRoom).evaluate().isNotEmpty && scene().ready,
      'initial room',
    );
    await until(() => scene().lastReadyRoom == 'living', 'living model');
    expect(find.text('Кто в коробке?'), findsOneWidget);
    expect(find.byKey(const ValueKey('adopt-start')), findsNothing);
    await capture('adoption-box');
    for (final choice in {1: 'puppy', 2: 'hamster'}.entries) {
      await tester.tap(find.byKey(ValueKey('adopt-species-${choice.key}')));
      await until(
        () => scene().ready && scene().lastReadySpecies == choice.value,
        'preview ${choice.value}',
      );
    }
    await tester.tap(find.byKey(const ValueKey('adopt-species-0')));
    await until(
      () => scene().ready && scene().lastReadySpecies == 'kitten',
      'selected kitten loaded',
    );
    await tester.tap(find.text('Имя и окрас'));
    await tester.pumpAndSettle();
    for (final coat in {2: 'fur_02', 3: 'fur_03', 1: 'fur_01'}.entries) {
      await tester.tap(find.text('Окрас ${coat.key}'));
      await until(
        () => scene().ready && scene().lastReadyColor == coat.value,
        'selected coat ${coat.value} loaded',
      );
    }
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await capture('adoption-kitten');
    await tester.ensureVisible(find.byKey(const ValueKey('adopt-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adopt-start')));
    await until(
      () =>
          find.byType(GameShell).evaluate().isNotEmpty &&
          tester
                  .widget<GameShell>(find.byType(GameShell))
                  .controller
                  .state!
                  .name !=
              null,
      'chosen pet saved',
    );
    await until(
      () => find.byType(SharedRoom).evaluate().isNotEmpty && scene().ready,
      'home scene after adoption',
    );
    expect((await store.load()).name, 'Персик');
    debugPrint('SCENE_INITIAL ${jsonEncode(scene().diagnostics)}');
    expect(scene().ready, isTrue);
    await capture('home');

    await tester.tap(find.byKey(const ValueKey('scene-budget')));
    await tester.pumpAndSettle();
    for (final entry in {
      'Забота': '15',
      'Желания': '5',
      'Накопления': '20',
    }.entries) {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == entry.key,
      );
      await tester.scrollUntilVisible(field, 180, scrollable: verticalScroll());
      await tester.pumpAndSettle();
      await tester.enterText(field, entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Подтвердить план'),
      160,
      scrollable: verticalScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить план'));
    final controller = tester
        .widget<GameShell>(find.byType(GameShell))
        .controller;
    await until(
      () => controller.state!.planConfirmed,
      'initial plan through UI',
    );
    expect((await store.load()).plan, [15, 5, 20]);
    await tester.tap(find.text('Дом'));
    await tester.pumpAndSettle();

    ScaffoldMessenger.of(
      tester.element(find.byType(GameShell)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scene-lamp')));
    await until(() => controller.state!.lampOn == false, 'lamp persisted off');
    expect((await store.load()).lampOn, isFalse);
    await until(() => scene().lastContactAction == 'lamp', 'lamp contact');

    await tester.tap(find.byKey(const ValueKey('scene-room-bathroom')));
    await until(() => scene().lastReadyRoom == 'bathroom', 'browse bathroom');
    await tester.tap(find.byKey(const ValueKey('scene-show-next')));
    await until(() => scene().lastReadyRoom == 'kitchen', 'kitchen loaded');
    await until(
      () => scene().lastGuidanceAction == 'wash_dishes',
      'Show points at the dish sink without starting the job',
    );
    expect(scene().dish.active, isFalse);
    expect((await store.load()).wallet[0], 100);
    await capture('guidance');
    expect((await store.load()).currentRoom, 'kitchen');
    await tester.tap(find.byKey(const ValueKey('scene-care')));
    await until(
      () => find.text('Да · 10 монет').evaluate().isNotEmpty,
      'food confirmation',
    );
    expect((await store.load()).wallet[0], 100);
    await tester.tap(find.text('Да · 10 монет'));
    await until(
      () => scene().lastContactAction == 'feed',
      'food contact after committed payment',
    );
    expect((await store.load()).wallet[0], 90);
    expect((await store.load()).needs[0], 85);
    expect(
      (await store.financialHistory()).where((e) => e['kind'] == 'care').length,
      1,
    );
    await capture('kitchen');

    Future<void> startDishes() async {
      await tester.tap(find.byKey(const ValueKey('scene-job')));
      await until(() => scene().dish.stage == 'scrub', 'dishwashing starts');
    }

    Future<void> dishStep(String nextStage, [int? cleaned]) async {
      await tester.tap(find.byKey(const ValueKey('dish-step')));
      await until(
        () =>
            scene().dish.stage == nextStage &&
            (cleaned == null || scene().dish.cleaned == cleaned),
        'dish step $nextStage $cleaned',
      );
    }

    await startDishes();
    await dishStep('scrub', 1);
    await tester.tap(find.byKey(const ValueKey('dish-cancel')));
    await until(() => !scene().dish.active, 'cancel unfinished dishes');
    expect((await store.load()).wallet[0], 90);
    expect((await store.load()).incomeAvailable, isTrue);
    for (var round = 0; round < 2; round++) {
      await startDishes();
      expect(scene().dish.cleaned, 0);
      for (var n = 1; n <= 6; n++) {
        await dishStep(n == 6 ? 'rinse' : 'scrub', n);
        if (round == 0 && n == 2) await capture('dishes');
      }
      await dishStep('water_off');
      expect((await store.load()).wallet[0], round == 0 ? 90 : 120);
      await dishStep('idle');
      expect((await store.load()).wallet[0], 120);
      expect((await store.load()).incomeAvailable, isFalse);
    }
    expect(
      (await store.financialHistory())
          .where((e) => e['kind'] == 'reward')
          .length,
      1,
    );

    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('scene-room-bathroom')))
          .onTap,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('scene-room-bathroom')));
    await until(
      () => scene().lastReadyRoom == 'bathroom',
      'bathroom via living',
    );
    await controller.change('Питомец в тестовом профиле', (s) => s.species = 2);
    await tester.pump();
    await until(() => scene().lastReadySpecies == 'hamster', 'hamster loaded');
    await tester.tap(find.byKey(const ValueKey('scene-care')));
    await until(
      () => find.text('Да · 5 монет').evaluate().isNotEmpty,
      'sand bath confirmation',
    );
    expect(find.text('Почистить шёрстку в песочной ванночке?'), findsOneWidget);
    await tester.tap(find.text('Позже'));
    await tester.pump(const Duration(seconds: 1));
    expect((await store.load()).wallet[0], 120);
    await tester.tap(find.byKey(const ValueKey('scene-care')));
    await until(
      () => find.text('Да · 5 монет').evaluate().isNotEmpty,
      'retry sand care',
    );
    await tester.tap(find.text('Да · 5 монет'));
    await until(
      () => scene().lastContactAction == 'clean',
      'species-specific clean contact',
    );
    expect((await store.load()).wallet[0], 115);
    await capture('bathroom');

    await tester.tap(find.byKey(const ValueKey('scene-room-living')));
    await until(() => scene().lastReadyRoom == 'living', 'living reloaded');
    final snapshot = (await store.load()).toJson();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await store.close();
    store = await GameStore.open(path: path);
    expect((await store.load()).toJson(), snapshot);
    await tester.pumpWidget(KopilychApp(store: store));
    await until(
      () => find.byType(SharedRoom).evaluate().isNotEmpty && scene().ready,
      'offline reload',
    );
    expect((await store.load()).species, 2);
    expect((await store.load()).lampOn, isFalse);
    expect((await store.load()).wallet[0], 115);
    expect(tester.takeException(), isNull);
    await capture('restored');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await store.close();
  });
}
