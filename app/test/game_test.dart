import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/meshy_pet_view.dart';

void main() {
  test('Need meters drain over eight hours and persist the elapsed anchor', () {
    final start = DateTime(2026, 9, 29, 10);
    final state = GameState()
      ..name = 'Листик'
      ..needs = [100, 80, 1];
    state.markAdopted(start);
    expect(state.needsResume(start.add(const Duration(minutes: 4))), isFalse);
    state.resume(start.add(const Duration(minutes: 4, seconds: 48)));
    expect(state.needs, [99, 79, 0]);
    final restored = GameState.fromJson(state.toJson());
    restored.resume(start.add(const Duration(hours: 8)));
    expect(restored.needs, [0, 0, 0]);
    expect(
      restored.needsUpdatedAtMs,
      start.add(const Duration(hours: 8)).millisecondsSinceEpoch,
    );
  });

  test('Daily login pays once on a later date and ignores clock rollback', () {
    final first = DateTime(2026, 9, 28, 12);
    final state = GameState()..name = 'Листик';
    state.markAdopted(first);
    state.resume(first);
    expect(state.wallet[0], 100);
    final next = first.add(const Duration(days: 1));
    state.resume(next);
    expect(state.wallet[0], 110);
    state.resume(next.add(const Duration(hours: 1)));
    state.resume(first);
    expect(state.wallet[0], 110);
    expect(state.lastLoginDate, '2026-09-29');
    final restored = GameState.fromJson(state.toJson());
    restored.resume(next.add(const Duration(hours: 2)));
    expect(restored.wallet[0], 110);
  });

  test('Job pays 30, 35 or 40 once; lesson shares the period income cap', () {
    final lesson = missions.firstWhere(
      (mission) => mission.period == 'daily' && mission.kind != 'action',
    );
    for (final (fast, happy, expected) in [
      (false, false, 30),
      (true, false, 35),
      (false, true, 35),
      (true, true, 40),
    ]) {
      final state = GameState()..currentRoom = 'kitchen';
      state.confirmPlan([20, 0, 10]);
      expect(
        state.finishDishJob(
          period: state.day,
          completedQuickly: fast,
          petHappy: happy,
        ),
        expected,
      );
      expect(state.wallet[0], 100 + expected);
      expect(
        state.finishDishJob(
          period: state.day,
          completedQuickly: true,
          petHappy: true,
        ),
        0,
      );
      expect(
        state.finish(
          lesson,
          lesson.correct,
          DateTime(2026, 9, 29),
          withoutHint: true,
        ),
        0,
      );
      expect(state.wallet[0], 100 + expected);
    }

    final lessonFirst = GameState()..currentRoom = 'kitchen';
    lessonFirst.confirmPlan([20, 0, 10]);
    expect(
      lessonFirst.finish(
        lesson,
        lesson.correct,
        DateTime(2026, 9, 29),
        withoutHint: true,
      ),
      30,
    );
    expect(
      lessonFirst.finishDishJob(
        period: lessonFirst.day,
        completedQuickly: true,
        petHappy: true,
      ),
      0,
    );
    expect(lessonFirst.wallet[0], 130);
  });

  test('Budget example conserves transfers and debits all care', () {
    final s = GameState();
    for (var i = 0; i < 3; i++) {
      s.care(i);
    }
    s.transfer(0, 1, 50);
    s.transfer(0, 2, 20);
    expect(s.wallet, [15, 50, 20]);
    expect(s.total, 85);
    expect(() => s.transfer(0, 1, 16), throwsA(isA<GameRule>()));
    expect(() => s.transfer(0, 1, -1), throwsA(isA<GameRule>()));
    expect(s.wallet, [15, 50, 20]);
  });
  test('Play is free while food and species care use canon prices', () {
    final s = GameState()..needs = [0, 0, 0];
    expect([s.careCost(0), s.careCost(1), s.careCost(2)], [10, 0, 5]);
    s.care(1);
    expect(s.wallet, [100, 0, 0]);
    expect(s.takePendingFinanceMutations(), isEmpty);
    s.care(0);
    s.care(2);
    expect(s.wallet, [85, 0, 0]);
  });
  test('Water is a free idempotent care mark', () {
    final s = GameState();
    s.giveWater();
    s.giveWater();
    expect(s.wallet, [100, 0, 0]);
    expect(s.completed.where((entry) => entry == 'care:water:1'), hasLength(1));
    expect(s.takePendingFinanceMutations(), isEmpty);
  });
  test('Sound preference defaults on and survives save roundtrip', () {
    final defaults = GameState();
    expect(defaults.soundEnabled, isTrue);
    defaults.soundEnabled = false;
    expect(GameState.fromJson(defaults.toJson()).soundEnabled, isFalse);

    final legacy = Map<String, dynamic>.from(defaults.toJson())
      ..remove('soundEnabled');
    expect(GameState.fromJson(legacy).soundEnabled, isTrue);
  });
  test(
    'Graphics quality defaults to auto, persists, and repairs unknown saved modes',
    () {
      final state = GameState();
      expect(state.graphicsQuality, 'auto');
      state.graphicsQuality = 'high';
      expect(GameState.fromJson(state.toJson()).graphicsQuality, 'high');
      final legacy = Map<String, dynamic>.from(state.toJson())
        ..remove('graphicsQuality');
      expect(GameState.fromJson(legacy).graphicsQuality, 'auto');
      for (final bad in ['ultra', 42, null]) {
        expect(
          GameState.fromJson({
            ...state.toJson(),
            'graphicsQuality': bad,
          }).graphicsQuality,
          'auto',
        );
      }
      state.graphicsQuality = 'ultra';
      expect(state.validate, throwsFormatException);
    },
  );
  test('Goals cannot be bought twice and changing goal retains savings', () {
    final s = GameState()..wallet = [0, 150, 0];
    s.goalId = 'garden';
    expect(s.wallet[1], 150);
    s.buyGoal();
    expect(s.wallet[1], 50);
    expect(() => s.buyGoal(), throwsA(isA<GameRule>()));
    expect(s.wallet[1], 50);
  });
  test('Wrong choices, same period, clock rollback and week boundaries', () {
    final s = GameState()..confirmPlan([20, 0, 10]);
    final date = DateTime(2026, 9, 14);
    expect(
      () => s.finish(missions[1], 0, date, withoutHint: false),
      throwsA(isA<GameRule>()),
    );
    expect(s.total, 100);
    expect(s.finish(missions[1], 1, date, withoutHint: true), 30);
    expect(s.finish(missions[1], 1, date, withoutHint: true), 0);
    expect(
      s.finish(
        missions[1],
        1,
        date.subtract(const Duration(days: 1)),
        withoutHint: true,
      ),
      0,
    );
    expect(
      s.finish(
        missions[1],
        1,
        date.add(const Duration(days: 1)),
        withoutHint: true,
      ),
      0,
    );
    s.endDay();
    s.confirmPlan([20, 0, 10]);
    s.setCurrentRoom('kitchen');
    expect(s.finishDishJob(period: s.day), 30);
    expect(s.period(missions[9], DateTime(2026, 9, 20)), '2026-09-14');
    expect(s.period(missions[9], DateTime(2026, 9, 21)), '2026-09-21');
  });
  test(
    'Every mission rejects wrong branches and rewards correct branch once',
    () {
      for (final m in missions) {
        if (m.kind == 'action') continue;
        final s = GameState()..confirmPlan([20, 0, 10]);
        for (var i = 0; i < m.options.length; i++) {
          if (i == m.correct) continue;
          expect(
            () => s.finish(m, i, DateTime(2026), withoutHint: false),
            throwsA(isA<GameRule>()),
          );
          expect(s.total, 100);
        }
        s.finish(m, m.correct, DateTime(2026), withoutHint: false);
        s.finish(m, m.correct, DateTime(2026), withoutHint: false);
        expect(s.total, 130);
        expect(s.independent, isEmpty);
      }
    },
  );
  test('Growth uses confirmed periods, care and net savings, not wealth', () {
    final s = GameState();
    final earning = missions.firstWhere(
      (mission) => mission.period == 'daily' && mission.kind != 'action',
    );
    for (var period = 1; period <= 5; period++) {
      s.needs = [0, 0, 0];
      s.confirmPlan([20, 0, 10]);
      s.finish(
        earning,
        earning.correct,
        DateTime(2026, 9, period),
        withoutHint: true,
      );
      for (var i = 0; i < 3; i++) {
        s.care(i);
      }
      s.transfer(0, 1, 10);
      s.endDay(reviewed: true, explanation: 'Забота стоила 15 монет');
      if (period == 3) expect(s.stage, 2);
    }
    expect(s.stage, 3);
    expect(s.owned, isEmpty, reason: 'growth must not require a goal purchase');
    expect(s.facts.every((fact) => fact.netSavings == 10), isTrue);
  });
  test('Offline return does not decay needs; schema roundtrips', () {
    final s = GameState()
      ..name = 'Листик'
      ..species = 2
      ..accessory = 1;
    final copy = GameState.fromJson(s.toJson());
    copy.period(missions[1], DateTime(2030));
    expect(copy.needs, s.needs);
    expect(copy.toJson(), s.toJson());
    expect(
      () => GameState.fromJson({...s.toJson(), 'schema': 99}),
      throwsFormatException,
    );
  });
  test(
    'Plan confirms once per day, respects wallet, and snapshots on endDay',
    () {
      final s = GameState();
      expect(() => s.confirmPlan([0, 0, 0]), throwsA(isA<GameRule>()));
      expect(() => s.confirmPlan([90, 5, 10]), throwsA(isA<GameRule>()));
      s.confirmPlan([40, 20, 10]);
      expect(s.planConfirmed, isTrue);
      expect(s.plansConfirmed, 1);
      expect(() => s.confirmPlan([30, 20, 10]), throwsA(isA<GameRule>()));
      s.confirmPlan([30, 20, 10], reason: 'income_received');
      expect(s.plansConfirmed, 1, reason: 'повтор в тот же день не считается');
      s.endDay();
      expect(s.facts.single.day, 1);
      expect(s.facts.single.plan, [30, 20, 10]);
      expect(s.facts.single.baselinePlan, [40, 20, 10]);
      expect(s.facts.single.revisedPlan, [30, 20, 10]);
      expect(s.facts.single.planVersions.length, 2);
      expect(s.planConfirmed, isFalse);
      s.endDay();
      expect(s.facts.length, 1, reason: 'день без плана не добавляет факт');
      expect(() => GameState.fromJson(s.toJson()), returnsNormally);
    },
  );
  test(
    'Catalog care and room care share one daily charge; wishes are unique',
    () {
      final s = GameState();
      final food = catalogItems.firstWhere((i) => i.id == 'food_refill');
      final ball = catalogItems.firstWhere((i) => i.id == 'ball');
      s.buyItem(food);
      s.buyItem(food);
      s.care(0);
      expect(s.purchased.where((id) => id == 'food_refill').length, 1);
      expect(s.needs[0], 85, reason: 'Повтор не прибавляет заботу или расходы');
      s.buyItem(ball);
      expect(() => s.buyItem(ball), throwsA(isA<GameRule>()));
      expect(s.total, 100 - food.price - ball.price);
      s.wallet = [0, 0, 0];
      expect(() => s.buyItem(food), returnsNormally);
      s.endDay();
      expect(() => s.buyItem(food), throwsA(isA<GameRule>()));
    },
  );
  test('Wearables cost once, equip only when owned, and survive a reload', () {
    final s = GameState();
    final cap = catalogItems.firstWhere((i) => i.id == 'cap');
    final bow = catalogItems.firstWhere((i) => i.id == 'bow');
    expect(() => s.toggleWearable('bow'), throwsA(isA<GameRule>()));
    s.buyItem(cap);
    expect(s.equippedWearable, 'cap');
    expect(s.visibleAccessory, 3);
    s.toggleWearable('cap');
    expect(s.equippedWearable, isNull);
    s.buyItem(bow);
    expect(s.equippedWearable, 'bow');
    expect(s.visibleAccessory, 4);
    expect(() => s.buyItem(bow), throwsA(isA<GameRule>()));
    expect(s.wallet[0], 100 - cap.price - bow.price);
    final copy = GameState.fromJson(s.toJson());
    expect(copy.equippedWearable, 'bow');
    copy.toggleWearable('cap');
    expect(copy.equippedWearable, 'cap');
    copy.resetProgress();
    expect(copy.equippedWearable, isNull);
    expect(() => copy.toggleWearable('cap'), throwsA(isA<GameRule>()));
  });
  test('Old cap owner migrates to a worn cap', () {
    final old = GameState().toJson()
      ..['schema'] = 4
      ..['purchased'] = ['cap']
      ..remove('equippedWearable');
    final restored = GameState.fromJson(old);
    expect(restored.equippedWearable, 'cap');
    expect(restored.toJson()['schema'], 9);
    expect(
      () =>
          GameState.fromJson({...restored.toJson(), 'equippedWearable': 'bow'}),
      throwsFormatException,
    );
  });
  test('Every species and wearable preview uses its species base GLB', () {
    for (final (index, name) in ['kitten', 'puppy', 'hamster'].indexed) {
      expect(
        MeshyPetView.assetFor(index, null),
        'assets/models/$name-mobile.glb',
      );
      for (final wearable in ['cap', 'bow']) {
        expect(
          MeshyPetView.assetFor(index, wearable),
          'assets/models/$name-mobile.glb',
        );
      }
    }
  });
  test('Action missions require a real action and pay once', () {
    final s = GameState();
    final plan = missions.firstWhere((m) => m.id == 'A01');
    final saved = missions.firstWhere((m) => m.id == 'A02');
    final shop = missions.firstWhere((m) => m.id == 'A03');
    expect(
      () => s.finish(plan, 0, DateTime(2026), withoutHint: true),
      throwsA(isA<GameRule>()),
    );
    s.confirmPlan([10, 0, 0]);
    expect(s.finish(plan, 0, DateTime(2026), withoutHint: true), 30);
    s.transfer(0, 1, 10);
    expect(s.finish(saved, 0, DateTime(2026), withoutHint: true), 0);
    s.buyItem(catalogItems.firstWhere((i) => i.id == 'stickers'));
    expect(s.finish(shop, 0, DateTime(2026), withoutHint: true), 0);
    expect(s.finish(shop, 0, DateTime(2026), withoutHint: true), 0);
    expect(s.plansConfirmed, 1);
    expect(s.completed.length, 3);
  });
  test('Demo profile provides five periods and survives reload', () {
    final s = GameState()..name = 'Персик';
    s.applyDemoProfile();
    expect(s.demoMode, isTrue);
    expect(s.facts.length, 5);
    expect(s.wallet[1], 90);
    expect(s.stage, 1, reason: 'synthetic demo facts are not growth evidence');
    s.achievedStage = 3;
    s.applyDemoProfile();
    expect(
      s.stage,
      1,
      reason: 'a fresh demo does not inherit another profile’s stage',
    );
    expect(s.facts.every((fact) => fact.synthetic && !fact.factKnown), isTrue);
    final copy = GameState.fromJson(s.toJson());
    expect(copy.facts.length, 5);
    expect(copy.demoMode, isTrue);
    expect(copy.toJson(), s.toJson());
  });
  test('Fact records real categories and net deposits minus withdrawals', () {
    final s = GameState();
    final ball = catalogItems.firstWhere((item) => item.id == 'ball');
    final mission = missions.firstWhere((item) => item.kind != 'action');
    s.confirmPlan([20, 20, 20]);
    s.care(0);
    s.buyItem(ball);
    s.transfer(0, 1, 20);
    s.transfer(1, 0, 5);
    s.finish(mission, mission.correct, DateTime(2026), withoutHint: true);
    s.endDay();
    final fact = s.facts.single;
    expect(fact.mandatorySpent, 10);
    expect(fact.wantsSpent, ball.price);
    expect(fact.savingsDeposits, 20);
    expect(fact.savingsWithdrawals, 5);
    expect(fact.netSavings, 15);
    expect(fact.income, 30);
  });
  test('Goal purchase is separate from current-wallet wants and reloads', () {
    final s = GameState()
      ..wallet = [25, 115, 0]
      ..needs = [0, 0, 0];
    s.confirmPlan([20, 0, 5]);
    for (var care = 0; care < 3; care++) {
      s.care(care);
    }
    s.transfer(0, 1, 5);
    s.buyGoal();
    s.endDay();
    final fact = s.facts.single;
    expect(fact.revisedPlan, [20, 0, 5]);
    expect(fact.mandatorySpent, 15);
    expect(fact.wantsSpent, 0);
    expect(fact.goalSpent, 120);
    expect(fact.netSavings, 5);
    final restored = GameState.fromJson(s.toJson()).facts.single;
    expect(restored.factKnown, isTrue);
    expect(restored.wantsSpent, 0);
    expect(restored.goalSpent, 120);
  });
  test('Legacy facts stay unknown and scene state validates', () {
    final legacy = GameState().toJson()
      ..['schema'] = 5
      ..remove('currentRoom')
      ..remove('lampOn')
      ..remove('planVersions')
      ..remove('periodActivity')
      ..['facts'] = [
        const DayFact(1, [10, 10, 10], [40, 30, 20], true).toJson()
          ..remove('planVersions')
          ..remove('mandatorySpent')
          ..remove('wantsSpent')
          ..remove('savingsDeposits')
          ..remove('savingsWithdrawals')
          ..remove('goalSpent')
          ..remove('income')
          ..remove('synthetic'),
      ];
    final restored = GameState.fromJson(legacy);
    expect(restored.facts.single.factKnown, isFalse);
    expect(restored.facts.single.netSavings, isNull);
    final incompleteCurrent = GameState().toJson();
    (incompleteCurrent['periodActivity'] as Map<String, dynamic>).remove(
      'goalSpent',
    );
    expect(GameState.fromJson(incompleteCurrent).periodActivity.known, isFalse);
    expect(restored.currentRoom, 'living');
    expect(restored.lampOn, isTrue);
    restored.setCurrentRoom('bathroom');
    restored.toggleLamp();
    final copy = GameState.fromJson(restored.toJson());
    expect(copy.currentRoom, 'bathroom');
    expect(copy.currentLampOn, isFalse);
    expect(copy.bathroomLampOn, isFalse);
    expect(copy.lampOn, isTrue);
    expect(copy.kitchenLampOn, isTrue);
    expect(
      () => GameState.fromJson({...copy.toJson(), 'currentRoom': 'roof'}),
      throwsFormatException,
    );
  });
  test('Achieved stage never drops when weaker facts replace old facts', () {
    final s = GameState();
    final earning = missions.firstWhere(
      (mission) => mission.period == 'daily' && mission.kind != 'action',
    );
    for (var period = 1; period <= 5; period++) {
      s.needs = [0, 0, 0];
      s.confirmPlan([20, 0, 10]);
      s.finish(
        earning,
        earning.correct,
        DateTime(2026, 10, period),
        withoutHint: true,
      );
      for (var care = 0; care < 3; care++) {
        s.care(care);
      }
      s.transfer(0, 1, 10);
      s.endDay(reviewed: true, explanation: 'Забота стоила 15 монет');
    }
    expect(s.stage, 3);
    for (var period = 6; period <= 10; period++) {
      s.confirmPlan([1, 0, 0]);
      s.endDay();
    }
    expect(
      s.facts.every((fact) => !fact.caredAll && fact.netSavings == 0),
      isTrue,
    );
    expect(s.stage, 3);
    expect(GameState.fromJson(s.toJson()).stage, 3);
  });
  test('V5 migration preserves legacy stage floor without inventing facts', () {
    GameState migrate({
      Set<String> completed = const {},
      Set<String> independent = const {},
      Set<String> owned = const {},
      int careDays = 0,
      int plansConfirmed = 0,
    }) {
      final json = GameState().toJson()
        ..['schema'] = 5
        ..['completed'] = completed.toList()
        ..['independent'] = independent.toList()
        ..['owned'] = owned.toList()
        ..['careDays'] = careDays
        ..['plansConfirmed'] = plansConfirmed
        ..remove('achievedStage');
      return GameState.fromJson(json);
    }

    expect(migrate().stage, 1);
    final stageTwo = migrate(
      completed: {'M01', 'M10'},
      careDays: 1,
      plansConfirmed: 1,
    );
    expect(stageTwo.stage, 2);
    expect(stageTwo.facts, isEmpty);
    final stageThree = migrate(
      completed: {'M01', 'M12'},
      independent: {'M12'},
      owned: {'garden'},
      careDays: 1,
      plansConfirmed: 1,
    );
    expect(stageThree.stage, 3);
    expect(stageThree.facts, isEmpty);
  });
  test('Reset keeps pet and settings but clears economy and plans', () {
    final s = GameState()
      ..name = 'Бублик'
      ..species = 1
      ..reducedMotion = true
      ..soundEnabled = false;
    s.applyDemoProfile();
    s.resetProgress();
    expect(s.name, 'Бублик');
    expect(s.species, 1);
    expect(s.reducedMotion, isTrue);
    expect(s.soundEnabled, isFalse);
    expect(s.total, 100);
    expect(s.completed, isEmpty);
    expect(s.purchased, isEmpty);
    expect(s.facts, isEmpty);
    expect(s.plansConfirmed, 0);
    expect(s.stage, 1);
    expect(s.demoMode, isFalse);
  });
}
