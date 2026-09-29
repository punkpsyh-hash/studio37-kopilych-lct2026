import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/story.dart';

const coreIds = {'B02', 'B04', 'S01', 'S02', 'P01', 'P06'};

void markLesson(GameState state, String id, int day) {
  state.completed
    ..add(id)
    ..add('canon:$id:$day');
}

DayFact reviewedFact(int day, {int dream = 10}) => DayFact(
  day,
  const [15, 0, 10],
  [70 - day, dream * day, 5],
  true,
  planVersions: const [
    PlanVersion([15, 10, 15], 'baseline'),
    PlanVersion([15, 0, 25], 'После дохода уточняю суммы'),
  ],
  mandatorySpent: 15,
  wantsSpent: 0,
  savingsDeposits: dream,
  savingsWithdrawals: 0,
  goalSpent: 0,
  income: 30,
  planFactReviewed: true,
  planFactExplanation: 'Желание отложили, поэтому увеличили накопления',
);

GameState completedRoute({required bool boughtGoal}) {
  final state = GameState()
    ..name = 'Персик'
    ..day = 6
    ..wallet = boughtGoal ? [30, 5, 5] : [30, 125, 5]
    ..facts = [for (var day = 1; day <= 5; day++) reviewedFact(day)]
    ..completed.add('canon:ball-deferred:1');

  for (var day = 1; day <= 5; day++) {
    for (final id in ['B02', 'B04', 'S02']) {
      markLesson(state, id, day);
    }
  }
  markLesson(state, 'S01', 1);
  markLesson(state, 'S01', 4);
  markLesson(state, 'P01', 1);
  markLesson(state, 'P06', 5);

  for (final entry in const [('J02', 2), ('J03', 3), ('J04', 4), ('J05', 5)]) {
    state.completed.add('job:${entry.$1}');
    state.rewards.add('job:${entry.$1}:${entry.$2}');
  }
  if (boughtGoal) {
    state.owned.add('house');
    state.completed.add('canon:goal-achieved:5');
  } else {
    state.completed.add('canon:goal-deferred:5');
  }
  return state;
}

void main() {
  test('canonical route exposes exactly six core IDs across five periods', () {
    final state = GameState()..name = 'Персик';
    final chapters = storyChapters(state);

    expect(chapters, hasLength(6), reason: 'prologue plus five periods');
    expect({
      for (final chapter in chapters)
        for (final task in chapter.tasks)
          if (coreIds.contains(task.target)) task.target,
    }, coreIds);
    expect(
      chapters
          .expand((chapter) => chapter.tasks)
          .where((task) => task.target.startsWith('M')),
      isEmpty,
      reason: 'legacy M01..M15 stay supplementary',
    );
  });

  test('P01 is routed before any paid household work', () {
    final state = GameState()..name = 'Персик';

    expect(storyActiveTask(state)?.target, 'S01');
    markLesson(state, 'S01', 1);
    expect(storyActiveTask(state)?.target, 'B02');
    markLesson(state, 'B02', 1);

    expect(storyActiveTask(state)?.target, 'P01');
    expect(state.periodActivity.income, 0);
    expect(state.incomeAvailable, isTrue);

    final targets = storyChapters(
      state,
    ).expand((chapter) => chapter.tasks).map((task) => task.target).toList();
    expect(targets.indexOf('P01'), lessThan(targets.indexOf('job:J02')));
  });

  test('late lesson marker recovers an abandoned earlier period', () {
    final state = GameState()
      ..name = 'Персик'
      ..day = 8;
    markLesson(state, 'B02', 1);

    expect(storyActiveTask(state)?.target, 'S01');
    markLesson(state, 'S01', 8);
    expect(storyActiveTask(state)?.target, 'P01');

    state.completed.add('P01');
    expect(
      storyActiveTask(state)?.target,
      'P01',
      reason: 'a legacy bare ID is not the canonical completion contract',
    );
    state.completed.add('canon:P01:8');
    expect(storyActiveTask(state)?.target, 'B04');
  });

  test('already full needs do not leave an impossible care step', () {
    final state = GameState()
      ..name = 'Персик'
      ..needs = [100, 100, 100];
    for (final id in ['S01', 'B02', 'P01', 'B04']) {
      markLesson(state, id, 1);
    }

    expect(
      storyActiveTask(state)?.target,
      'catalog',
      reason: 'care() correctly refuses to charge or mark a full need',
    );
  });

  test('synthetic and unknown migrated facts do not complete a review', () {
    final synthetic = reviewedFact(1);
    final unknown = DayFact(
      2,
      const [15, 0, 10],
      const [70, 10, 5],
      true,
      planFactReviewed: true,
    );
    final state = GameState()
      ..name = 'Персик'
      ..facts = [
        DayFact.fromJson({...synthetic.toJson(), 'synthetic': true}),
        unknown,
      ];

    final firstReview = storyChapters(
      state,
    )[1].tasks.firstWhere((task) => task.target == 'day');
    expect(firstReview.done, isFalse);

    state.facts = [...state.facts, reviewedFact(3)];
    expect(
      storyChapters(
        state,
      )[1].tasks.firstWhere((task) => task.target == 'day').done,
      isTrue,
    );
  });

  test('bought goal and deferred expensive goal reach the same finale', () {
    final bought = completedRoute(boughtGoal: true);
    final deferred = completedRoute(boughtGoal: false);

    expect(bought.wallet, [30, 5, 5]);
    expect(bought.owned, contains('house'));
    expect(currentChapter(bought), 6);

    expect(deferred.wallet, [30, 125, 5]);
    expect(deferred.owned, isEmpty);
    expect(currentChapter(deferred), 6);
    expect(storyChapters(deferred).last.ending, contains('честный результат'));
  });

  test('finale waits for an explicit goal purchase or defer decision', () {
    final state = completedRoute(boughtGoal: false)
      ..completed.remove('canon:goal-deferred:5')
      ..wallet = [30, 0, 130];

    final task = storyActiveTask(state);
    expect(task?.target, 'dreams');
    expect(task?.secondaryTarget, 'defer:dream');
    expect(task?.label, contains('не хватает'));

    state.completed.add('canon:goal-deferred:6');
    expect(currentChapter(state), 6);
  });

  test('an older owned goal does not claim the current goal was bought', () {
    final state = completedRoute(boughtGoal: false)
      ..owned.add('garden')
      ..goalId = 'stars';

    expect(currentChapter(state), 6);
    expect(storyChapters(state).last.ending, contains('честный результат'));
  });

  test('an achieved finale stays complete after selecting another goal', () {
    final state = completedRoute(boughtGoal: true)..goalId = 'stars';

    expect(currentChapter(state), 6);
    expect(storyChapters(state).last.ending, contains('появилась в доме'));
  });

  test('story getters survive reload and never change money or state', () {
    final state = completedRoute(boughtGoal: false);
    final before = jsonEncode(state.toJson());

    for (var i = 0; i < 5; i++) {
      expect(currentChapter(state), 6);
      expect(storyActiveTask(state), isNull);
      expect(storyChapters(state), hasLength(6));
    }

    expect(jsonEncode(state.toJson()), before);
    final reloaded = GameState.fromJson(jsonDecode(before));
    expect(reloaded.wallet, [30, 125, 5]);
    expect(currentChapter(reloaded), 6);
    expect(jsonEncode(reloaded.toJson()), before);
  });
}
