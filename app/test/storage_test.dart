import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late GameStore store;
  setUp(() async {
    store = await GameStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.close();
  });
  test('Controller reports calendar login bonus once after persisted resume', () async {
    await store.change('adopt:bonus', 'Выбор питомца', (state) {
      state.name = 'Пушок';
      state.markAdopted(DateTime.now().subtract(const Duration(days: 2)));
      state.needsUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
    });
    final controller = GameController(store);
    await controller.load();
    expect(controller.loginBonusAwarded, 10);
    expect(controller.state!.wallet[0], 110);
    await controller.load();
    expect(controller.loginBonusAwarded, 0);
    expect(controller.state!.wallet[0], 110);
    controller.dispose();
  });
  test('Graphics quality survives storage and demo profile creation', () async {
    await store.change('quality:high', 'Качество графики', (s) {
      s.graphicsQuality = 'high';
    });
    expect((await store.load()).graphicsQuality, 'high');
    expect((await store.startDemo()).graphicsQuality, 'high');
    expect((await store.exitDemo()).graphicsQuality, 'high');
  });
  test(
    'Wearable purchase retries debit once and equip state persists',
    () async {
      final bow = catalogItems.firstWhere((i) => i.id == 'bow');
      await store.change('buy-bow', 'Бантик', (s) => s.buyItem(bow));
      await store.change('buy-bow', 'Бантик', (s) => s.buyItem(bow));
      final saved = await store.load();
      expect(saved.wallet[0], 100 - bow.price);
      expect(saved.equippedWearable, 'bow');
      expect((await store.history()).length, 1);
      await store.change(
        'remove-bow',
        'Снять бантик',
        (s) => s.toggleWearable('bow'),
      );
      expect((await store.load()).equippedWearable, isNull);
      expect((await store.load()).wallet[0], 100 - bow.price);
    },
  );
  test(
    'SQLite failure after ledger insert rolls back the full transaction',
    () async {
      await store.db.execute(
        "CREATE TRIGGER fail_save BEFORE UPDATE ON state BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
      await expectLater(
        store.change('care-retry', 'Корм', (s) => s.care(0)),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.load()).total, 100);
      expect(await store.history(), isEmpty);
      await store.db.execute('DROP TRIGGER fail_save');
      await store.change('care-retry', 'Корм', (s) => s.care(0));
      expect((await store.load()).total, 90);
      expect((await store.history()).length, 1);
    },
  );
  test('Real version 1 SQLite database migrates and reopens intact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kopilych-migration-',
    );
    final path = '${directory.path}/v1.db';
    final old = GameState().toJson()
      ..['schema'] = 1
      ..['wallet'] = [10, 50, 20]
      ..['name'] = 'Персик'
      ..remove('independent')
      ..remove('reducedMotion')
      ..remove('soundEnabled');
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE operations (id TEXT PRIMARY KEY, label TEXT NOT NULL, delta INTEGER NOT NULL, created TEXT NOT NULL)',
          );
          await db.insert('state', {'id': 1, 'data': jsonEncode(old)});
        },
      ),
    );
    await db.close();
    final migrated = await GameStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    expect(await migrated.db.getVersion(), 9);
    expect((await migrated.load()).wallet, [10, 50, 20]);
    expect((await migrated.load()).name, 'Персик');
    await migrated.close();
    final reopened = await GameStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    expect((await reopened.load()).wallet, [10, 50, 20]);
    await reopened.close();
    // Only remove the exact fixture file created by this test, inside systemTemp.
    await File(path).delete();
  });
  test('Concurrent duplicate applies once and history agrees', () async {
    await Future.wait(
      List.generate(
        10,
        (_) =>
            store.change('transfer:1', 'Перевод', (s) => s.transfer(0, 1, 50)),
      ),
    );
    expect((await store.load()).wallet, [50, 50, 0]);
    expect((await store.history()).length, 1);
    expect((await store.history()).single['delta'], 0);
    final events = await store.financialHistory();
    expect(events.length, 1);
    expect(events.single['kind'], 'transfer');
    expect(events.single['category'], 'savings');
    expect(events.single['amount'], 50);
  });
  test('Failure rolls back money and journal', () async {
    await expectLater(
      store.change('crash', 'Сбой', (s) {
        s.care(0);
        throw StateError('simulated');
      }),
      throwsStateError,
    );
    expect((await store.load()).total, 100);
    expect(await store.history(), isEmpty);
    await store.change('care', 'Корм', (s) => s.care(0));
    expect((await store.load()).total, 90);
    expect((await store.history()).single['delta'], -10);
  });
  test('Invalid snapshot is preserved instead of reset', () async {
    await store.db.update('state', {'data': 'broken'}, where: 'id=1');
    await expectLater(store.load(), throwsFormatException);
    expect((await store.db.query('state')).single['data'], 'broken');
  });
  test('Version 1 adds defaults without losing wallet', () {
    final old = GameState().toJson()
      ..['schema'] = 1
      ..['wallet'] = [10, 50, 20]
      ..remove('independent')
      ..remove('reducedMotion');
    final upgraded = GameState.fromJson(old);
    expect(upgraded.wallet, [10, 50, 20]);
    expect(upgraded.reducedMotion, false);
    expect(upgraded.soundEnabled, true);
    expect(upgraded.toJson()['schema'], 9);
  });
  test('Version 5 migration preserves rows and marks detail unknown', () async {
    await store.close();
    final directory = await Directory.systemTemp.createTemp(
      'kopilych-v5-migration-',
    );
    final path = '${directory.path}/v5.db';
    final old = GameState().toJson()
      ..['schema'] = 5
      ..remove('currentRoom')
      ..remove('lampOn')
      ..remove('planVersions')
      ..remove('periodActivity')
      ..['facts'] = [
        const DayFact(1, [20, 10, 10], [50, 30, 20], true).toJson()
          ..remove('planVersions')
          ..remove('mandatorySpent')
          ..remove('wantsSpent')
          ..remove('savingsDeposits')
          ..remove('savingsWithdrawals')
          ..remove('goalSpent')
          ..remove('income')
          ..remove('synthetic'),
      ];
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE operations (id TEXT PRIMARY KEY, label TEXT NOT NULL, delta INTEGER NOT NULL, created TEXT NOT NULL)',
          );
          await db.insert('state', {'id': 1, 'data': jsonEncode(old)});
          await db.insert('operations', {
            'id': 'legacy-transfer',
            'label': 'Старый перевод',
            'delta': 0,
            'created': '2026-09-20T12:00:00.000',
          });
        },
      ),
    );
    await legacy.close();
    final migrated = await GameStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    final state = await migrated.load();
    expect(await migrated.db.getVersion(), 9);
    expect(state.facts.single.factKnown, isFalse);
    expect(state.facts.single.netSavings, isNull);
    expect(state.currentRoom, 'living');
    expect(state.lampOn, isTrue);
    final event = (await migrated.financialHistory()).single;
    expect(event['kind'], 'unknown');
    expect(event['category'], 'unknown');
    expect(event['amount'], isNull);
    await migrated.close();
    await File(path).delete();
    store = await GameStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  test(
    'Compound action stores every typed event and duplicate is inert',
    () async {
      await store.change(
        'plan',
        'Исходный план',
        (s) => s.confirmPlan([20, 0, 10]),
      );
      Future<void> run() => store.change('compound', 'Забота и перевод', (s) {
        s.care(0);
        s.transfer(0, 1, 10);
      });
      await run();
      await run();
      expect((await store.load()).wallet, [80, 10, 0]);
      await store.change('close', 'Закрыть период', (s) => s.endDay());
      final saved = await store.load();
      expect(saved.facts.single.mandatorySpent, 10);
      expect(saved.facts.single.savingsDeposits, 10);
      expect(saved.facts.single.netSavings, 10);
      final events = (await store.financialHistory())
          .where((event) => event['category'] != null)
          .toList();
      expect(events.length, 2);
      expect(events.map((event) => event['kind']).toSet(), {
        'care',
        'transfer',
      });
      expect((await store.history()).length, 3);
    },
  );
  test('Room and lamp persist and duplicate toggle applies once', () async {
    await store.change(
      'room:kitchen',
      'Перейти на кухню',
      (s) => s.setCurrentRoom('kitchen'),
    );
    await store.change('lamp:1', 'Выключить свет', (s) => s.toggleLamp());
    await store.change('lamp:1', 'Выключить свет', (s) => s.toggleLamp());
    final saved = await store.load();
    expect(saved.currentRoom, 'kitchen');
    expect(saved.currentLampOn, isFalse);
    expect(saved.kitchenLampOn, isFalse);
    expect(saved.lampOn, isTrue);
    expect(saved.bathroomLampOn, isTrue);
  });
  test(
    'Owned fixtures persist independently without financial events',
    () async {
      final original = await store.load();
      await store.change('fixture:owned', 'Светильники', (s) {
        s.owned.add('stars');
        s.purchased.add('nightlight');
      });
      await store.change('stars:1', 'Звёздный уголок', (s) {
        s.toggleOptionalFixture('stars');
      });
      await store.change('stars:1', 'Повторное подтверждение', (s) {
        s.toggleOptionalFixture('stars');
      });
      var saved = await store.load();
      expect(saved.starsOn, isFalse);
      expect(saved.nightlightOn, isTrue);
      expect(saved.lampOn, isTrue);
      await store.change('nightlight:1', 'Ночник', (s) {
        s.toggleOptionalFixture('nightlight');
      });
      saved = await store.load();
      expect(saved.nightlightOn, isFalse);
      expect(saved.starsOn, isFalse);
      expect(saved.wallet, original.wallet);
      expect(
        (await store.financialHistory()).where(
          (event) => event['category'] != null,
        ),
        isEmpty,
      );
      expect(
        () => GameState().toggleOptionalFixture('stars'),
        throwsA(isA<GameRule>()),
      );
      expect(
        () => GameState().toggleOptionalFixture('nightlight'),
        throwsA(isA<GameRule>()),
      );
      final legacy = saved.toJson()
        ..remove('starsOn')
        ..remove('nightlightOn');
      final restored = GameState.fromJson(legacy);
      expect(restored.starsOn, isTrue);
      expect(restored.nightlightOn, isTrue);
    },
  );
  test('Compound closure keeps events on their actual periods', () async {
    final mission = missions.firstWhere(
      (item) => item.period == 'daily' && item.kind != 'action',
    );
    await store.change(
      'plan-period-1',
      'Исходный план',
      (s) => s.confirmPlan([10, 0, 0]),
    );
    await store.change('cross-period', 'Закрытие и новый доход', (s) {
      s.care(0);
      s.endDay();
      s.confirmPlan([10, 0, 10]);
      s.finish(
        mission,
        mission.correct,
        DateTime(2026, 9, 24),
        withoutHint: true,
      );
    });
    final events = (await store.financialHistory())
        .where((event) => event['operation_id'] == 'cross-period')
        .toList();
    expect(events.map((event) => event['period']).toSet(), {1, 2});
    final saved = await store.load();
    expect(saved.facts.single.mandatorySpent, 10);
    expect(saved.facts.single.income, 0);
    expect(saved.periodActivity.income, 30);
  });
  test('All financial methods write typed ledger categories', () async {
    final mission = missions.firstWhere(
      (item) => item.kind != 'action' && item.period == 'daily',
    );
    final ball = catalogItems.firstWhere((item) => item.id == 'ball');
    await store.change('full-period', 'Полный финансовый период', (s) {
      s.confirmPlan([10, 15, 75]);
      s.finish(
        mission,
        mission.correct,
        DateTime(2026, 9, 24),
        withoutHint: true,
      );
      s.care(0);
      s.buyItem(ball);
      s.transfer(0, 1, 100);
      s.goalId = 'garden';
      s.buyGoal();
      s.endDay();
    });
    final events = (await store.financialHistory())
        .where((event) => event['operation_id'] == 'full-period')
        .toList();
    expect(events.map((event) => event['kind']).toSet(), {
      'reward',
      'care',
      'purchase',
      'transfer',
      'goal_purchase',
    });
    final fact = (await store.load()).facts.single;
    expect(fact.mandatorySpent, 10);
    expect(fact.wantsSpent, 15);
    expect(fact.goalSpent, 100);
    expect(fact.savingsDeposits, 100);
    expect(fact.savingsWithdrawals, 0);
    expect(fact.income, 30);
  });
}
