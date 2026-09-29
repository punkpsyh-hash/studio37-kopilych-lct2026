import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/mission_page.dart';
import 'package:kopilych/onboarding.dart';
import 'package:kopilych/ui.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
    'Home and budget remain usable with large text on a small screen',
    (tester) async {
      sqfliteFfiInit();
      final store = await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      );
      final controller = GameController(store!)
        ..state = (GameState()
          ..name = 'Листик'
          ..reducedMotion = true);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: GameShell(controller: controller, useMeshyModels: false),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Завершить день'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Бюджет'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('История монет'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(store.close);
    },
  );
  testWidgets(
    'All species selectable and blank name reaches default-name handler',
    (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      int? picked;
      String? name;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Onboarding(
            busy: false,
            onStart: (species, color, accessory, value) async {
              picked = species;
              name = value;
              return true;
            },
          ),
        ),
      );
      for (final label in speciesNames) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      await tester.scrollUntilVisible(
        find.text('Это мой друг'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Это мой друг'));
      await tester.pump();
      expect(picked, 2);
      expect(name, '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Practice never invokes wallet or progress mutation; alternatives render',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MissionPage(
            mission: missions.firstWhere((mission) => mission.id == 'M06'),
            practice: true,
            onComplete: (a, b) async {
              calls++;
              return 30;
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('85 монет'), 180);
      await tester.tap(find.text('85 монет'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
      await tester.tap(find.text('Проверить решение'));
      await tester.pumpAndSettle();
      expect(find.text('Тренировка завершена'), findsOneWidget);
      expect(calls, 0);
      await tester.scrollUntilVisible(
        find.text('Сравнить игрушку и домик'),
        180,
      );
      await tester.tap(find.text('Сравнить игрушку и домик'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Купить игрушку'));
      await tester.pumpAndSettle();
      expect(find.text('Игрушка уже у тебя'), findsOneWidget);
      expect(calls, 0);
    },
  );
  testWidgets('M01 does not offer the unrelated toy comparison', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MissionPage(
          mission: missions.firstWhere((mission) => mission.id == 'M01'),
          practice: true,
          onComplete: (_, _) async =>
              throw StateError('Practice must not save'),
        ),
      ),
    );
    await tester.tap(find.text('30 монет'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
    await tester.tap(find.text('Проверить решение'));
    await tester.pumpAndSettle();
    expect(find.text('Тренировка завершена'), findsOneWidget);
    expect(find.text('Сравнить игрушку и домик'), findsNothing);
    expect(find.text('Попробовать иначе'), findsNothing);
  });
  testWidgets('Wrong answer gives explanation and correct retry records hint', (
    tester,
  ) async {
    bool? independent;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MissionPage(
          mission: missions[0],
          practice: false,
          onComplete: (a, b) async {
            independent = b;
            return 30;
          },
        ),
      ),
    );
    await tester.tap(find.text('70 монет'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
    await tester.tap(find.text('Проверить решение'));
    await tester.pumpAndSettle();
    expect(find.text('Давай разберём вместе'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('30 монет'), -180);
    await tester.tap(find.text('30 монет'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Проверить решение'), 180);
    await tester.tap(find.text('Проверить решение'));
    await tester.pumpAndSettle();
    expect(independent, false);
    expect(find.text('+30 монет в «Сейчас»'), findsOneWidget);
  });
  testWidgets(
    'Small viewport and 200 percent text keep onboarding scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Onboarding(busy: false, onStart: (a, b, c, d) async => true),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Это мой друг'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
