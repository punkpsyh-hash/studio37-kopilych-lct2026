import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<GameStore> openMemoryStore() =>
      GameStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);

  test('demo has independent state, ledger, idempotency, and reset', () async {
    final store = await openMemoryStore();
    addTearDown(store.close);

    await store.change('pet', 'Выбор питомца', (state) {
      state
        ..name = 'Ириска'
        ..species = 1
        ..color = 4
        ..accessory = 2
        ..reducedMotion = true
        ..soundEnabled = false;
    });
    await store.change('same-operation', 'Основная забота', (state) {
      state.care(0);
    });
    final mainStateRows = await store.db.query('state');
    final mainOperations = await store.db.query('operations');
    final mainEvents = await store.db.query('operation_events');

    var demo = await store.startDemo();
    expect(demo.demoMode, isTrue);
    expect(demo.name, 'Ириска');
    expect(demo.species, 1);
    expect(demo.color, 4);
    expect(demo.accessory, 2);
    expect(demo.reducedMotion, isTrue);
    expect(demo.soundEnabled, isFalse);
    expect(demo.day, 1);
    expect(demo.wallet, [100, 0, 0]);
    expect(demo.facts, isEmpty);
    expect(demo.plansConfirmed, 0);
    expect(await store.history(), isEmpty);

    // The same id is valid once in each profile's independent namespace.
    await store.change('same-operation', 'Демо-забота', (state) {
      state.care(0);
    });
    expect((await store.load()).wallet, [90, 0, 0]);
    expect((await store.history()).single['id'], 'same-operation');
    expect(
      (await store.financialHistory()).single['operation_id'],
      'same-operation',
    );

    final main = await store.exitDemo();
    expect(main.demoMode, isFalse);
    expect(main.wallet, [90, 0, 0]);
    expect(await store.db.query('state'), mainStateRows);
    expect(await store.db.query('operations'), mainOperations);
    expect(await store.db.query('operation_events'), mainEvents);

    demo = await store.startDemo();
    expect(demo.wallet, [90, 0, 0], reason: 'repeated start resumes demo');
    demo = await store.resetDemo();
    expect(demo.demoMode, isTrue);
    expect(demo.name, 'Ириска');
    expect(demo.species, 1);
    expect(demo.color, 4);
    expect(demo.accessory, 2);
    expect(demo.reducedMotion, isTrue);
    expect(demo.soundEnabled, isFalse);
    expect(demo.day, 1);
    expect(demo.wallet, [100, 0, 0]);
    expect(demo.facts, isEmpty);
    expect(await store.history(), isEmpty);
    expect(await store.financialHistory(), isEmpty);
  });

  test('active demo selection survives database reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kopilych-demo-profile-',
    );
    final path = '${directory.path}/profiles.db';
    try {
      var store = await GameStore.open(path: path, factory: databaseFactoryFfi);
      await store.startDemo();
      await store.change('demo-care', 'Демо-забота', (state) => state.care(0));
      await store.close();

      store = await GameStore.open(path: path, factory: databaseFactoryFfi);
      final selected = await store.load();
      expect(selected.demoMode, isTrue);
      expect(selected.wallet, [90, 0, 0]);
      expect(
        (await store.db.query('profile_selection')).single['active'],
        'demo',
      );
      expect((await store.history()).single['id'], 'demo-care');
      await store.close();
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test(
    'failed switch rolls back demo creation and controller recovers',
    () async {
      final store = await openMemoryStore();
      addTearDown(store.close);
      await store.change(
        'main-care',
        'Основная забота',
        (state) => state.care(0),
      );
      final mainStateRows = await store.db.query('state');
      final mainOperations = await store.db.query('operations');
      final mainEvents = await store.db.query('operation_events');
      final controller = GameController(store)..state = await store.load();
      final before = controller.state!.toJson();

      await store.db.execute(
        "CREATE TRIGGER fail_demo_switch BEFORE UPDATE ON profile_selection "
        "WHEN NEW.active='demo' BEGIN "
        "SELECT RAISE(ABORT, 'simulated switch failure'); END",
      );
      await expectLater(
        controller.startDemo(),
        throwsA(isA<DatabaseException>()),
      );

      expect(controller.busy, isFalse);
      expect(controller.loadError, isNull);
      expect(controller.state!.toJson(), before);
      expect(await store.db.query('demo_state'), isEmpty);
      expect(
        (await store.db.query('profile_selection')).single['active'],
        'main',
      );
      expect(await store.db.query('state'), mainStateRows);
      expect(await store.db.query('operations'), mainOperations);
      expect(await store.db.query('operation_events'), mainEvents);

      await store.db.execute('DROP TRIGGER fail_demo_switch');
      await controller.startDemo();
      expect(controller.busy, isFalse);
      expect(controller.loadError, isNull);
      expect(controller.state!.demoMode, isTrue);
    },
  );

  test('controller GameRule keeps usable state and load status', () async {
    final store = await openMemoryStore();
    addTearDown(store.close);
    final controller = GameController(store)..state = await store.load();
    final before = controller.state!.toJson();

    await expectLater(
      controller.change('Недоступное действие', (_) {
        throw const GameRule('Проверяемое правило игры');
      }),
      throwsA(isA<GameRule>()),
    );

    expect(controller.busy, isFalse);
    expect(controller.loadError, isNull);
    expect(controller.state!.toJson(), before);
  });

  test('failed demo reset rolls back its state and full ledger', () async {
    final store = await openMemoryStore();
    addTearDown(store.close);
    await store.startDemo();
    await store.change('demo-care', 'Демо-забота', (state) => state.care(0));
    final demoStateRows = await store.db.query('demo_state');
    final demoOperations = await store.db.query('demo_operations');
    final demoEvents = await store.db.query('demo_operation_events');

    await store.db.execute(
      "CREATE TRIGGER fail_demo_reset BEFORE INSERT ON demo_state BEGIN "
      "SELECT RAISE(ABORT, 'simulated reset failure'); END",
    );
    await expectLater(store.resetDemo(), throwsA(isA<DatabaseException>()));

    expect(
      (await store.db.query('profile_selection')).single['active'],
      'demo',
    );
    expect(await store.db.query('demo_state'), demoStateRows);
    expect(await store.db.query('demo_operations'), demoOperations);
    expect(await store.db.query('demo_operation_events'), demoEvents);
    expect((await store.load()).wallet, [90, 0, 0]);
  });

  test(
    'v7 legacy demo flag migrates to authoritative main selection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kopilych-v7-demo-migration-',
      );
      final path = '${directory.path}/v7.db';
      try {
        final legacyState = GameState()..applyDemoProfile();
        final legacyJson = legacyState.toJson()..['schema'] = 7;
        final legacy = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 7,
            onCreate: (db, version) async {
              await db.execute(
                'CREATE TABLE state '
                '(id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)',
              );
              await db.execute(
                'CREATE TABLE operations '
                '(id TEXT PRIMARY KEY, label TEXT NOT NULL, '
                'delta INTEGER NOT NULL, created TEXT NOT NULL)',
              );
              await db.execute(
                'CREATE TABLE operation_events ('
                'operation_id TEXT NOT NULL REFERENCES operations(id) '
                'ON DELETE CASCADE, sequence INTEGER NOT NULL, period INTEGER, '
                'kind TEXT NOT NULL, category TEXT, amount INTEGER, '
                'from_wallet INTEGER, to_wallet INTEGER, '
                'PRIMARY KEY(operation_id, sequence))',
              );
              await db.insert('state', {
                'id': 1,
                'data': jsonEncode(legacyJson),
              });
              await db.insert('operations', {
                'id': 'legacy-demo-operation',
                'label': 'Старая демо-операция',
                'delta': 0,
                'created': '2026-09-27T00:00:00.000',
              });
              await db.insert('operation_events', {
                'operation_id': 'legacy-demo-operation',
                'sequence': 0,
                'period': 6,
                'kind': 'state',
                'amount': 0,
              });
            },
          ),
        );
        await legacy.close();

        final store = await GameStore.open(
          path: path,
          factory: databaseFactoryFfi,
        );
        final migrated = await store.load();
        expect(await store.db.getVersion(), 9);
        expect(migrated.demoMode, isFalse);
        expect(migrated.wallet, legacyState.wallet);
        expect(migrated.day, legacyState.day);
        expect(migrated.facts.length, legacyState.facts.length);
        expect(
          (await store.db.query('profile_selection')).single['active'],
          'main',
        );
        expect((await store.history()).single['id'], 'legacy-demo-operation');
        expect(await store.db.query('demo_operations'), isEmpty);
        await store.close();
      } finally {
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );

  test('wipe removes both profiles and selects a fresh main profile', () async {
    final store = await openMemoryStore();
    addTearDown(store.close);
    await store.change(
      'main-care',
      'Основная забота',
      (state) => state.care(0),
    );
    await store.startDemo();
    await store.change('demo-care', 'Демо-забота', (state) => state.care(0));

    await store.wipe();

    final fresh = await store.load();
    expect(fresh.demoMode, isFalse);
    expect(fresh.wallet, [100, 0, 0]);
    expect(await store.db.query('operations'), isEmpty);
    expect(await store.db.query('operation_events'), isEmpty);
    expect(await store.db.query('demo_state'), isEmpty);
    expect(await store.db.query('demo_operations'), isEmpty);
    expect(await store.db.query('demo_operation_events'), isEmpty);
    expect(
      (await store.db.query('profile_selection')).single['active'],
      'main',
    );
  });
}
