import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/adult_page.dart';
import 'package:kopilych/budget_page.dart';
import 'package:kopilych/catalog_page.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/mission_page.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/story_page.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const captureKey = ValueKey('secondary-page-capture');

Widget frame(Widget page, {double textScale = 1}) => MaterialApp(
  theme: appTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: RepaintBoundary(key: captureKey, child: page),
);

Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['CAPTURE_SECONDARY_UI'] != '1') return;
  await expectLater(
    find.byKey(captureKey),
    matchesGoldenFile('goldens/secondary-ui/$name.png'),
  );
}

void configurePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  setUpAll(() async {
    final nunito = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-400.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([nunito.load(), materialIcons.load()]);
  });

  testWidgets('Mission and story use the warm game palette at 360 px', (
    tester,
  ) async {
    configurePhone(tester);
    await tester.pumpWidget(
      frame(
        MissionPage(
          mission: missions.first,
          practice: true,
          onComplete: (reward, independent) async => 0,
        ),
        textScale: 2,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('30 монет'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('30 монет'));
    await tester.pump();
    await tester.tap(find.text('30 монет'));
    await tester.pump();
    final selected = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('30 монет'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(selected.style?.backgroundColor?.resolve(<WidgetState>{}), sage);
    expect(tester.takeException(), isNull);
    await capture(tester, 'mission-360-text200');

    final state = GameState()..name = 'Персик';
    await tester.pumpWidget(
      frame(
        Scaffold(
          body: StoryPage(state: state, onGo: (_) {}, onCelebrate: () {}),
        ),
        textScale: 2,
      ),
    );
    await tester.pump();
    await capture(tester, 'story-360-text200');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Сравнить три мечты и выбрать свою'),
      220,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Budget, catalog, and adult stay usable at 360 px', (
    tester,
  ) async {
    configurePhone(tester);
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    final initial = await tester.runAsync(
      () => store!.change('secondary-style-setup', 'Выбор котёнка', (state) {
        state.name = 'Персик';
        state.species = 0;
        state.reducedMotion = true;
      }),
    );
    final controller = GameController(store!)..state = initial;
    Future<bool> action(
      String label,
      void Function(GameState) change, {
      String? success,
      String? id,
    }) async => true;

    await tester.pumpWidget(
      frame(
        Scaffold(
          body: BudgetPage(
            controller: controller,
            onAction: action,
            onDreams: () {},
            useMeshyModels: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await capture(tester, 'budget-360');

    await tester.pumpWidget(
      frame(
        CatalogPage(
          controller: controller,
          onAction: action,
          useMeshyModels: false,
        ),
        textScale: 2,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Порция корма')).width, greaterThan(160));
    await capture(tester, 'catalog-360-text200');

    await tester.pumpWidget(
      frame(AdultPage(controller: controller), textScale: 2),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await capture(tester, 'adult-360-text200');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(store.close);
  });
}
