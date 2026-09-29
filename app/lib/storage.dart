import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'game.dart';

const _mainProfile = 'main';
const _demoProfile = 'demo';

({String state, String operations, String events}) _tables(String profile) =>
    profile == _demoProfile
    ? (
        state: 'demo_state',
        operations: 'demo_operations',
        events: 'demo_operation_events',
      )
    : (state: 'state', operations: 'operations', events: 'operation_events');

class GameStore {
  GameStore(this.db);
  final Database db;

  static Future<GameStore> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? '${await f.getDatabasesPath()}/kopilych.db';
    final database = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: (db) async {
          await db.execute('PRAGMA synchronous = FULL');
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createProfileTables(db, _mainProfile);
          await db.insert('state', {
            'id': 1,
            'data': jsonEncode(GameState().toJson()),
          });
          await _createDemoStorage(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 6) {
            final main = _tables(_mainProfile);
            await _createFinanceEvents(db, main);
            await db.execute(
              "INSERT INTO operation_events(operation_id, sequence, period, kind, category, amount) SELECT id, 0, NULL, 'unknown', 'unknown', NULL FROM operations",
            );
          }
          if (oldVersion < 8) await _createDemoStorage(db);

          // Snapshot migration preserves balances and all historical facts.
          // The old demo flag described a destructive sample-state mutation;
          // profile_selection is authoritative from v8 onward.
          final rows = await db.query('state', where: 'id=1');
          final state = GameState.fromJson(
            jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
          );
          if (oldVersion < 8) state.demoMode = false;
          await db.update('state', {
            'data': jsonEncode(state.toJson()),
          }, where: 'id=1');
        },
      ),
    );
    return GameStore(database);
  }

  static Future<void> _createProfileTables(
    DatabaseExecutor db,
    String profile,
  ) async {
    final tables = _tables(profile);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${tables.state} '
      '(id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${tables.operations} '
      '(id TEXT PRIMARY KEY, label TEXT NOT NULL, delta INTEGER NOT NULL, '
      'created TEXT NOT NULL)',
    );
    await _createFinanceEvents(db, tables);
  }

  static Future<void> _createFinanceEvents(
    DatabaseExecutor db,
    ({String state, String operations, String events}) tables,
  ) => db.execute(
    'CREATE TABLE IF NOT EXISTS ${tables.events} ('
    'operation_id TEXT NOT NULL REFERENCES ${tables.operations}(id) '
    'ON DELETE CASCADE, sequence INTEGER NOT NULL, period INTEGER, '
    'kind TEXT NOT NULL, category TEXT, amount INTEGER, from_wallet INTEGER, '
    'to_wallet INTEGER, PRIMARY KEY(operation_id, sequence))',
  );

  static Future<void> _createDemoStorage(DatabaseExecutor db) async {
    await _createProfileTables(db, _demoProfile);
    await db.execute(
      "CREATE TABLE IF NOT EXISTS profile_selection ("
      "id INTEGER PRIMARY KEY CHECK(id=1), active TEXT NOT NULL "
      "CHECK(active IN ('main', 'demo')))",
    );
    await db.insert('profile_selection', {
      'id': 1,
      'active': _mainProfile,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String> _activeProfile(DatabaseExecutor executor) async {
    final rows = await executor.query('profile_selection', where: 'id=1');
    if (rows.length != 1) {
      throw const FormatException('Активный профиль не найден');
    }
    final profile = rows.single['active'];
    if (profile != _mainProfile && profile != _demoProfile) {
      throw const FormatException('Неизвестный активный профиль');
    }
    return profile! as String;
  }

  Future<GameState> _loadProfile(
    DatabaseExecutor executor,
    String profile,
  ) async {
    final rows = await executor.query(_tables(profile).state, where: 'id=1');
    if (rows.length != 1) throw const FormatException('Сохранение не найдено');
    return GameState.fromJson(
      jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
    );
  }

  Future<void> _selectProfile(DatabaseExecutor executor, String profile) async {
    final changed = await executor.update('profile_selection', {
      'active': profile,
    }, where: 'id=1');
    if (changed != 1) {
      throw const FormatException('Активный профиль не найден');
    }
  }

  GameState _blankDemoFrom(GameState source) => GameState()
    ..name = source.name
    ..species = source.species
    ..color = source.color
    ..accessory = source.accessory
    ..reducedMotion = source.reducedMotion
    ..soundEnabled = source.soundEnabled
    ..soundVolume = source.soundVolume
    ..voiceEnabled = source.voiceEnabled
    ..musicEnabled = source.musicEnabled
    ..musicVolume = source.musicVolume
    ..graphicsQuality = source.graphicsQuality
    ..demoMode = true;

  Future<GameState> load() => db.transaction((txn) async {
    final profile = await _activeProfile(txn);
    return _loadProfile(txn, profile);
  });

  Future<GameState> change(
    String operationId,
    String label,
    void Function(GameState) action,
  ) => db.transaction((txn) async {
    final profile = await _activeProfile(txn);
    final tables = _tables(profile);
    final state = await _loadProfile(txn, profile);
    if ((await txn.query(
      tables.operations,
      where: 'id=?',
      whereArgs: [operationId],
    )).isNotEmpty) {
      return state;
    }
    final before = state.total;
    final beforeWallet = List<int>.from(state.wallet);
    final period = state.day;
    action(state);
    state.demoMode = profile == _demoProfile;
    final finance = state.takePendingFinanceMutations();
    final snapshotReplacement = state.takeSnapshotReplacement();
    final walletChanged =
        state.wallet.length != beforeWallet.length ||
        List.generate(
          beforeWallet.length,
          (index) => state.wallet[index] != beforeWallet[index],
        ).any((changed) => changed);
    final unclassifiedWalletChange =
        finance.isEmpty && walletChanged && !snapshotReplacement;
    if (unclassifiedWalletChange) state.markPeriodActivityUnknown();
    state.validate();
    await txn.insert(tables.operations, {
      'id': operationId,
      'label': label,
      'delta': state.total - before,
      'created': DateTime.now().toIso8601String(),
    });
    if (finance.isEmpty) {
      await txn.insert(tables.events, {
        'operation_id': operationId,
        'sequence': 0,
        'period': period,
        'kind': unclassifiedWalletChange ? 'unknown' : 'state',
        'category': unclassifiedWalletChange ? 'unknown' : null,
        'amount': unclassifiedWalletChange ? null : 0,
      });
    } else {
      for (final (sequence, event) in finance.indexed) {
        if (!financeKinds.contains(event.kind) ||
            !financeCategories.contains(event.category) ||
            event.amount <= 0) {
          throw const FormatException('Некорректное финансовое событие');
        }
        await txn.insert(tables.events, {
          'operation_id': operationId,
          'sequence': sequence,
          'period': event.period ?? period,
          'kind': event.kind,
          'category': event.category,
          'amount': event.amount,
          'from_wallet': event.fromWallet,
          'to_wallet': event.toWallet,
        });
      }
    }
    await txn.update(tables.state, {
      'data': jsonEncode(state.toJson()),
    }, where: 'id=1');
    return state;
  });

  Future<List<Map<String, Object?>>> history() => db.transaction((txn) async {
    final profile = await _activeProfile(txn);
    return txn.query(
      _tables(profile).operations,
      orderBy: 'rowid DESC',
      limit: 60,
    );
  });

  Future<List<Map<String, Object?>>> financialHistory({int? period}) =>
      db.transaction((txn) async {
        final profile = await _activeProfile(txn);
        final tables = _tables(profile);
        return txn.rawQuery(
          'SELECT e.operation_id, e.sequence, e.period, e.kind, e.category, '
          'e.amount, e.from_wallet, e.to_wallet, o.label, o.created '
          'FROM ${tables.events} e JOIN ${tables.operations} o '
          'ON o.id=e.operation_id '
          '${period == null ? '' : 'WHERE e.period=? '} '
          'ORDER BY o.rowid DESC, e.sequence DESC LIMIT 120',
          period == null ? null : [period],
        );
      });

  Future<GameState> startDemo() => db.transaction((txn) async {
    final demoRows = await txn.query('demo_state', where: 'id=1');
    final GameState demo;
    if (demoRows.isEmpty) {
      demo = _blankDemoFrom(await _loadProfile(txn, _mainProfile));
      demo.validate();
      await txn.insert('demo_state', {
        'id': 1,
        'data': jsonEncode(demo.toJson()),
      });
    } else if (demoRows.length == 1) {
      demo = GameState.fromJson(
        jsonDecode(demoRows.single['data'] as String) as Map<String, dynamic>,
      );
    } else {
      throw const FormatException('Некорректное демо-сохранение');
    }
    await _selectProfile(txn, _demoProfile);
    return demo;
  });

  Future<GameState> exitDemo() => db.transaction((txn) async {
    final main = await _loadProfile(txn, _mainProfile);
    await _selectProfile(txn, _mainProfile);
    return main;
  });

  Future<GameState> resetDemo() => db.transaction((txn) async {
    final demoRows = await txn.query('demo_state', where: 'id=1');
    final source = demoRows.isEmpty
        ? await _loadProfile(txn, _mainProfile)
        : GameState.fromJson(
            jsonDecode(demoRows.single['data'] as String)
                as Map<String, dynamic>,
          );
    final demo = _blankDemoFrom(source)..validate();
    await txn.delete('demo_operation_events');
    await txn.delete('demo_operations');
    await txn.insert('demo_state', {
      'id': 1,
      'data': jsonEncode(demo.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _selectProfile(txn, _demoProfile);
    return demo;
  });

  /// Полное удаление данных: оба профиля и их журналы удаляются, а основное
  /// состояние сбрасывается к первому запуску. Используется только из раздела
  /// взрослого с явным подтверждением (§2.5.12, §3.5 ТЗ).
  Future<void> wipe() => db.transaction((txn) async {
    await txn.delete('demo_operation_events');
    await txn.delete('demo_operations');
    await txn.delete('demo_state');
    await txn.delete('operation_events');
    await txn.delete('operations');
    await txn.update('state', {
      'data': jsonEncode(GameState().toJson()),
    }, where: 'id=1');
    await _selectProfile(txn, _mainProfile);
  });

  Future<void> close() => db.close();
}
