import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';

void main() {
  final lesson = missions.firstWhere(
    (mission) => mission.period == 'daily' && mission.kind != 'action',
  );

  void completeQualifyingPeriod(GameState state) {
    state.needs = [0, 0, 0];
    state.confirmPlan([15, 0, 10]);
    final job = householdJobForPeriod(state.day);
    state.setCurrentRoom(job.room);
    state.finishJob(job.id, period: state.day);
    for (var need = 0; need < 3; need++) {
      state.care(need);
    }
    state.transfer(0, 1, 10);
    expect(state.currentPeriodSummary.hasPlanDeviation, isFalse);
    state.endDay(reviewed: true);
  }

  test('mission income follows manual periods, not the device calendar', () {
    final state = GameState()..confirmPlan([20, 0, 10]);
    final firstClock = DateTime(2026, 9, 27, 12);

    expect(
      state.finish(lesson, lesson.correct, firstClock, withoutHint: true),
      30,
    );
    expect(
      state.finish(
        lesson,
        lesson.correct,
        firstClock.add(const Duration(days: 40)),
        withoutHint: true,
      ),
      0,
    );
    expect(
      state.finish(
        lesson,
        lesson.correct,
        firstClock.subtract(const Duration(days: 40)),
        withoutHint: true,
      ),
      0,
    );
    expect(state.wallet, [130, 0, 0]);

    state.endDay();
    state.confirmPlan([20, 0, 10]);
    expect(
      state.finish(lesson, lesson.correct, firstClock, withoutHint: true),
      30,
    );
    expect(state.wallet, [160, 0, 0]);
  });

  test('schema 7 paid period cannot pay again after migration', () {
    final state = GameState()
      ..wallet = [70, 30, 15]
      ..achievedStage = 3;
    state.confirmPlan([20, 0, 10]);
    expect(
      state.finish(
        lesson,
        lesson.correct,
        DateTime(2026, 9, 27),
        withoutHint: true,
      ),
      30,
    );
    final old = state.toJson()
      ..['schema'] = 7
      ..remove('qualifyingPeriods');

    final restored = GameState.fromJson(old);
    expect(restored.wallet, [100, 30, 15]);
    expect(restored.stage, 3);
    expect(restored.qualifyingPeriods, 0);
    expect(
      restored.finish(
        lesson,
        lesson.correct,
        DateTime(2030),
        withoutHint: true,
      ),
      0,
    );
    expect(restored.wallet, [100, 30, 15]);
  });

  test('needs use canonical decay and never fall below twenty', () {
    final state = GameState();
    state.endDay();
    expect(state.needs, [48, 57, 45]);
    for (var period = 0; period < 20; period++) {
      state.endDay();
    }
    expect(state.needs, [20, 20, 20]);
  });

  test('review is atomic and deviations require an explanation', () {
    final state = GameState()..confirmPlan([20, 0, 10]);
    state.needs = [0, 0, 0];
    for (var need = 0; need < 3; need++) {
      state.care(need);
    }
    state.transfer(0, 1, 10);
    final summary = state.currentPeriodSummary;
    expect(summary.hasPlanDeviation, isTrue);
    expect(() => summary.plan[0] = 0, throwsUnsupportedError);
    final before = state.toJson();

    expect(() => state.endDay(reviewed: true), throwsA(isA<GameRule>()));
    expect(state.toJson(), before);

    state.endDay(
      reviewed: true,
      explanation: '  Забота стоила меньше плана.  ',
    );
    expect(state.qualifyingPeriods, 1);
    expect(state.facts.single.planFactReviewed, isTrue);
    expect(
      state.facts.single.planFactExplanation,
      'Забота стоила меньше плана.',
    );
    expect(state.facts.single.qualifiesForGrowth, isTrue);
  });

  test('the latest revised plan is compared with fact', () {
    final state = GameState()..confirmPlan([20, 0, 10]);
    state.needs = [0, 0, 0];
    for (var need = 0; need < 3; need++) {
      state.care(need);
    }
    state.transfer(0, 1, 10);
    state.confirmPlan([15, 0, 10], reason: 'Уточнили после расходов');

    expect(state.currentPeriodSummary.baselinePlan, [20, 0, 10]);
    expect(state.currentPeriodSummary.revisedPlan, [15, 0, 10]);
    expect(state.currentPeriodSummary.hasPlanDeviation, isFalse);
    state.endDay(reviewed: true);
    expect(state.facts.single.qualifiesForGrowth, isTrue);
  });

  test(
    'growth uses lifetime reviewed periods beyond the rolling five facts',
    () {
      final state = GameState();
      for (var period = 1; period <= 7; period++) {
        completeQualifyingPeriod(state);
        if (period == 3) expect(state.stage, 2);
        if (period == 5) expect(state.stage, 3);
      }

      expect(state.qualifyingPeriods, 7);
      expect(state.facts.length, 5);
      expect(state.facts.every((fact) => fact.qualifiesForGrowth), isTrue);
      final restored = GameState.fromJson(state.toJson());
      expect(restored.qualifyingPeriods, 7);
      expect(restored.stage, 3);
    },
  );

  for (final missingCondition in ['care', 'net saving']) {
    test('growth waits when a reviewed period misses $missingCondition', () {
      final state = GameState();
      completeQualifyingPeriod(state);
      completeQualifyingPeriod(state);

      state.needs = [0, 0, 0];
      if (missingCondition != 'care') {
        for (var need = 0; need < 3; need++) {
          state.care(need);
        }
      }
      final savings = missingCondition == 'net saving' ? 0 : 10;
      state.confirmPlan([missingCondition == 'care' ? 0 : 15, 0, savings]);
      if (savings > 0) state.transfer(0, 1, savings);
      state.endDay(reviewed: true);

      expect(state.qualifyingPeriods, 2);
      expect(state.stage, 1);
      expect(state.facts.last.synthetic, isFalse);
      expect(state.facts.last.qualifiesForGrowth, isFalse);

      completeQualifyingPeriod(state);
      expect(state.qualifyingPeriods, 3);
      expect(state.stage, 2);
    });
  }

  test('five cared and saved periods without review do not grant growth', () {
    final state = GameState();
    for (var period = 0; period < 5; period++) {
      state.needs = [0, 0, 0];
      state.confirmPlan([15, 0, 10]);
      final job = householdJobForPeriod(state.day);
      state.setCurrentRoom(job.room);
      state.finishJob(job.id, period: state.day);
      for (var need = 0; need < 3; need++) {
        state.care(need);
      }
      state.transfer(0, 1, 10);
      state.endDay();
    }

    expect(state.facts.length, 5);
    expect(
      state.facts.every((fact) => fact.caredAll && fact.netSavings == 10),
      isTrue,
    );
    expect(state.qualifyingPeriods, 0);
    expect(state.stage, 1);
  });

  test('unreviewed and legacy facts never invent growth credit', () {
    final state = GameState()..confirmPlan([15, 0, 10]);
    state.needs = [0, 0, 0];
    for (var need = 0; need < 3; need++) {
      state.care(need);
    }
    state.transfer(0, 1, 10);
    state.endDay();
    expect(state.facts.single.qualifiesForGrowth, isFalse);
    expect(state.qualifyingPeriods, 0);

    final old = state.toJson()
      ..['schema'] = 7
      ..['achievedStage'] = 2
      ..remove('qualifyingPeriods');
    final oldFact =
        Map<String, dynamic>.from(
            (old['facts'] as List).single as Map<String, dynamic>,
          )
          ..['planFactReviewed'] = true
          ..['planFactExplanation'] = 'Не должно импортироваться';
    old['facts'] = [oldFact];
    final migrated = GameState.fromJson(old);
    expect(migrated.stage, 2);
    expect(migrated.qualifyingPeriods, 0);
    expect(migrated.facts.single.planFactReviewed, isFalse);
    expect(migrated.facts.single.planFactExplanation, isNull);
  });

  test('review cannot close a period without a confirmed plan', () {
    final state = GameState();
    final before = state.toJson();
    expect(() => state.endDay(reviewed: true), throwsA(isA<GameRule>()));
    expect(state.toJson(), before);

    state.endDay();
    expect(state.day, 2);
    expect(state.facts, isEmpty);
  });

  test('maxDate accepts only real canonical dates or empty', () {
    for (final invalid in [
      'zzzz',
      '2026-2-03',
      '2026-02-30',
      '2026-09-27T12:00:00',
      ' 2026-09-27',
    ]) {
      expect(
        () => GameState.fromJson({...GameState().toJson(), 'maxDate': invalid}),
        throwsFormatException,
        reason: invalid,
      );
    }
    expect(
      GameState.fromJson({...GameState().toJson(), 'maxDate': ''}).maxDate,
      isEmpty,
    );
    expect(
      GameState.fromJson({
        ...GameState().toJson(),
        'maxDate': '2028-02-29',
      }).maxDate,
      '2028-02-29',
    );
  });
}
