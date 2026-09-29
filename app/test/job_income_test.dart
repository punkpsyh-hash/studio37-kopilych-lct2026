import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final lesson = missions.firstWhere((m) => m.kind != 'action');
  for (final jobFirst in [true, false]) {
    test('One income shared by job and lesson, jobFirst=$jobFirst', () {
      final s = GameState()..currentRoom = 'kitchen';
      expect(() => s.finishDishJob(period: 1), throwsA(isA<GameRule>()));
      expect(
        () =>
            s.finish(lesson, lesson.correct, DateTime(2026), withoutHint: true),
        throwsA(isA<GameRule>()),
      );
      expect(s.total, 100);
      s.confirmPlan([20, 0, 10]);
      int job() => s.finishDishJob(period: s.day);
      int quiz() =>
          s.finish(lesson, lesson.correct, DateTime(2026), withoutHint: true);
      expect(jobFirst ? job() : quiz(), 30);
      expect(jobFirst ? quiz() : job(), 0);
      expect(job(), 0);
      expect(s.total, 130);
      expect(s.completed, containsAll(['job:dishes', lesson.id]));
      expect(
        s.takePendingFinanceMutations().where((e) => e.kind == 'reward').length,
        1,
      );
      final restored = GameState.fromJson(s.toJson());
      expect(restored.incomeAvailable, isFalse);
      restored.endDay();
      restored.confirmPlan([20, 0, 10]);
      final snapshot = restored.toJson();
      expect(() => restored.finishDishJob(period: 1), throwsA(isA<GameRule>()));
      expect(restored.toJson(), snapshot);
      restored.setCurrentRoom('bathroom');
      expect(() => restored.finishDishJob(period: 2), throwsA(isA<GameRule>()));
      restored.setCurrentRoom('kitchen');
      expect(restored.finishDishJob(period: 2), 30);
      expect(restored.periodActivity.income, 30);
      expect(restored.total, 160);
    });
  }

  test(
    'Migration preserves money and conservatively starts legacy income next period',
    () {
      for (var schema = 1; schema <= 6; schema++) {
        final old = GameState().toJson()
          ..['schema'] = schema
          ..['wallet'] = [70, 30, 15]
          ..['periodActivity'] = const PeriodActivity(known: false).toJson();
        final s = GameState.fromJson(old);
        expect(s.wallet, [70, 30, 15]);
        expect(s.incomeAvailable, isFalse);
        s.setCurrentRoom('kitchen');
        s.confirmPlan([20, 0, 10]);
        expect(s.finishDishJob(period: 1), 0);
        s.endDay();
        s.confirmPlan([20, 0, 10]);
        expect(s.finishDishJob(period: 2), 30);
        expect(s.wallet, [100, 30, 15]);
      }
      for (final income in [0, 30, 90]) {
        final old = GameState().toJson()
          ..['schema'] = 6
          ..['periodActivity'] = PeriodActivity(income: income).toJson();
        expect(GameState.fromJson(old).incomeAvailable, income == 0);
      }
    },
  );

  test(
    'SQLite serializes duplicate and distinct reward attempts across reload',
    () async {
      sqfliteFfiInit();
      final store = await GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.close);
      await store.change('setup', 'План', (s) {
        s.confirmPlan([20, 0, 10]);
        s.setCurrentRoom('kitchen');
      });
      await Future.wait([
        store.change('dish:1', 'Посуда', (s) => s.finishDishJob(period: 1)),
        store.change(
          'dish:1',
          'Повтор сообщения',
          (s) => s.finishDishJob(period: 1),
        ),
        store.change(
          'dish:2',
          'Новая попытка',
          (s) => s.finishDishJob(period: 1),
        ),
      ]);
      expect((await store.load()).wallet, [130, 0, 0]);
      final income = (await store.financialHistory()).where(
        (e) => e['category'] == 'income',
      );
      expect(income.length, 1);
      expect(income.single['amount'], 30);
      await store.change('reset', 'Сброс', (s) => s.resetProgress());
      expect((await store.load()).incomeAvailable, isTrue);
      await store.change('demo', 'Демо', (s) => s.applyDemoProfile());
      expect((await store.load()).incomeAvailable, isFalse);
    },
  );

  test(
    'All canonical household jobs enforce room, period, and shared income',
    () {
      for (final job in householdJobs.values) {
        final s = GameState()..confirmPlan([20, 0, 10]);
        s.setCurrentRoom(job.room);
        expect(s.finishJob(job.id, period: 1), 30, reason: job.id);
        expect(s.finishJob(job.id, period: 1), 0, reason: '${job.id} replay');
        expect(s.completed, contains('job:${job.id}'));
        expect(s.total, 130);
      }
      final wrongRoom = GameState()..confirmPlan([20, 0, 10]);
      expect(
        () => wrongRoom.finishJob('J03', period: 1),
        throwsA(isA<GameRule>()),
      );
      expect(
        () => wrongRoom.finishJob('J99', period: 1),
        throwsA(isA<GameRule>()),
      );
    },
  );

  test('Different jobs in one period still share the single +30 cap', () {
    final s = GameState()
      ..confirmPlan([20, 0, 10])
      ..setCurrentRoom('living');
    expect(s.finishJob('J02', period: 1), 30);
    expect(s.finishJob('J05', period: 1), 0);
    expect(s.finishJob('J06', period: 1), 0);
    expect(s.total, 130);
    expect(
      s.takePendingFinanceMutations().where((e) => e.kind == 'reward').length,
      1,
    );
  });
}
