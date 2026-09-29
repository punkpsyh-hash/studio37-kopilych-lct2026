import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/story.dart';
import 'package:kopilych/story_page.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('dream choices rise in price using the existing canon goals', () {
    expect(goals.map((goal) => goal.id), ['garden', 'house', 'stars']);
    expect(goals.map((goal) => goal.price), [100, 120, 150]);
  });

  test('new friend follows room actions before the goal lesson', () {
    final state = GameState()
      ..name = 'Пушок'
      ..completed.add('intro-started');
    String? target() => firstDayGuide(state)?.target;

    expect(target(), 'play');
    state.care(1);
    expect(target(), 'B02');
    state.confirmPlan([15, 15, 20]);
    state.completed.addAll(['B02', 'canon:B02:1']);
    expect(target(), 'room:kitchen');
    state.setCurrentRoom('kitchen');
    expect(target(), 'care');
    state.care(0);
    expect(target(), 'room:bathroom');
    state.setCurrentRoom('bathroom');
    expect(target(), 'care');
    state.care(2);
    expect(target(), 'room:living');
    state.setCurrentRoom('living');
    expect(target(), 'catalog');
    state.buyItem(catalogItems.singleWhere((item) => item.id == 'ball'));
    expect(state.wallet, [70, 0, 0]);
    expect(target(), 'play');
    expect(state.needs[1], 100, reason: 'the purchased ball already raised joy');
    state.completed.add('intro-toy-play');
    expect(state.wallet, [70, 0, 0]);
    expect(target(), 'intro:money');
    state.completed.add('intro-money');
    expect(target(), 'S01');
    state.completed.addAll(['S01', 'canon:S01:1']);
    expect(target(), 'intro:goal');
    state.completed.add('intro-goal');
    expect(target(), isNull);

    final restored = GameState.fromJson(jsonDecode(jsonEncode(state.toJson())));
    expect(firstDayGuide(restored), isNull);
    expect(storyActiveTask(restored)?.target, 'P01');
  });

  test(
    'first basket has one toy payment and never repays daily care',
    () async {
      sqfliteFfiInit();
      final store = await GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.close);
      final ball = catalogItems.singleWhere((item) => item.id == 'ball');
      await store.change('care-first-day', 'Care', (state) {
        state.care(0);
        state.care(2);
      });
      Future<GameState> checkout() => store.change(
        'intro:first-basket:1',
        'First basket',
        (state) => state.buyItem(ball),
      );
      var state = await checkout();
      expect(state.wallet, [70, 0, 0]);
      state = await checkout();
      expect(state.wallet, [70, 0, 0]);
      expect(
        state.purchased,
        containsAll(['food_refill', 'clean_care', 'ball']),
      );
    },
  );

  test('old saves retain the canonical chapter route', () {
    final old = GameState()..name = 'Пушок';
    expect(firstDayGuide(old), isNull);
    expect(storyActiveTask(old)?.target, 'S01');
  });

  testWidgets('story page opens the first play action for a new friend', (
    tester,
  ) async {
    final state = GameState()
      ..name = 'Пушок'
      ..completed.add('intro-started');
    String? route;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: StoryPage(
            state: state,
            onGo: (target) => route = target,
            onCelebrate: () {},
          ),
        ),
      ),
    );
    final play = find.widgetWithText(
      FilledButton,
      'О, мячик! Поиграем в гостиной.',
    );
    await tester.scrollUntilVisible(play, 220);
    await tester.pumpAndSettle();
    await tester.tap(play.hitTestable());
    expect(route, 'play');
    expect(find.text('Сравнить три мечты и выбрать свою'), findsNothing);
  });
}
