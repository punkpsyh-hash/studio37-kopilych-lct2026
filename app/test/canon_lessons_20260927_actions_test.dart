import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';

void main() {
  CanonLessonSubmission submission(
    GameState state,
    String id, {
    bool practice = false,
    List<int>? split,
    String? reason,
    String? goalId,
    String? transferTarget,
    int? amount,
    List<String> basketIds = const [],
    String? rationale,
    bool purchaseAttempted = false,
    String? p06Resolution,
    int? attemptedAvailable,
    int? attemptedPrice,
    bool useTeachingCopy = false,
  }) => CanonLessonSubmission.capture(
    state,
    lessonId: id,
    practice: practice,
    split: split,
    reason: reason,
    goalId: goalId,
    transferTarget: transferTarget,
    amount: amount,
    basketIds: basketIds,
    rationale: rationale,
    purchaseAttempted: purchaseAttempted,
    p06Resolution: p06Resolution,
    attemptedAvailable: attemptedAvailable,
    attemptedPrice: attemptedPrice,
    useTeachingCopy: useTeachingCopy,
  );

  test('canonical curriculum leads and preserves all legacy missions', () {
    expect(canonicalMissions.map((mission) => mission.id), [
      'B02',
      'B04',
      'S01',
      'S02',
      'P01',
      'P06',
    ]);
    expect(missions, hasLength(15));
    expect(allMissions, hasLength(21));
    expect(allMissions.take(6), canonicalMissions);
    expect(isCanonicalLesson('P01'), isTrue);
    expect(isCanonicalLesson('M01'), isFalse);
  });

  test('B02 confirms a bounded real plan without moving money', () {
    final state = GameState();
    final beforeWallet = List<int>.from(state.wallet);

    final reward = submission(state, 'B02', split: [15, 10, 25]).apply(state);

    expect(reward, 0);
    expect(state.wallet, beforeWallet);
    expect(state.plan, [15, 10, 25]);
    expect(state.planVersions.single.reason, 'baseline');
    expect(state.completed, containsAll(['B02', 'canon:B02:1']));
  });

  test('B02 rejects overflow atomically', () {
    final state = GameState();
    final before = state.toJson();

    expect(
      () => submission(state, 'B02', split: [60, 30, 20]).apply(state),
      throwsA(isA<GameRule>()),
    );
    expect(state.toJson(), before);
  });

  test('B02 can recognize an existing baseline without rewriting it', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final versionsBefore = state.planVersions.length;

    expect(submission(state, 'B02', split: [15, 10, 15]).apply(state), 0);
    expect(state.planVersions, hasLength(versionsBefore));
    expect(state.completed, contains('canon:B02:1'));
  });

  test('B04 preserves the baseline and records an explained revision', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final job = householdJobForPeriod(state.day);
    state.setCurrentRoom(job.room);
    expect(state.finishJob(job.id, period: state.day), 30);

    expect(
      submission(
        state,
        'B04',
        split: [15, 0, 25],
        reason: 'После дохода уточняю суммы',
      ).apply(state),
      0,
    );

    expect(state.planVersions, hasLength(2));
    expect(state.planVersions.first.split, [15, 10, 15]);
    expect(state.planVersions.last.split, [15, 0, 25]);
    expect(state.planVersions.last.reason, 'После дохода уточняю суммы');
  });

  test('B04 cannot claim income before income exists', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final before = state.toJson();

    expect(
      () => submission(
        state,
        'B04',
        split: [15, 0, 25],
        reason: 'После дохода уточняю суммы',
      ).apply(state),
      throwsA(isA<GameRule>()),
    );
    expect(state.toJson(), before);
  });

  test('S01 changes the selected goal without losing savings', () {
    final state = GameState()..wallet = [25, 70, 5];

    expect(submission(state, 'S01', goalId: 'stars').apply(state), 0);

    expect(state.goalId, 'stars');
    expect(state.wallet, [25, 70, 5]);
    expect(state.completed, contains('canon:S01:1'));
  });

  test('S02 transfers real money and stale submissions are rejected', () {
    final state = GameState()..wallet = [40, 20, 10];
    final stale = submission(state, 'S02', transferTarget: 'dream', amount: 5);
    state.transfer(0, 2, 3);
    final changed = state.toJson();

    expect(() => stale.apply(state), throwsA(isA<GameRule>()));
    expect(state.toJson(), changed);

    final current = submission(
      state,
      'S02',
      transferTarget: 'dream',
      amount: 5,
    );
    expect(current.apply(state), 0);
    expect(state.wallet, [32, 25, 13]);
  });

  test('completed real submission is idempotent before stale checks', () {
    final state = GameState()..wallet = [40, 20, 10];
    final command = submission(
      state,
      'S02',
      transferTarget: 'reserve',
      amount: 5,
    );
    expect(command.apply(state), 0);
    expect(state.wallet, [35, 20, 15]);

    state.day = 2;
    state.wallet = [99, 1, 1];
    expect(command.apply(state), 0);
    expect(state.wallet, [99, 1, 1]);
  });

  test('practice validates its payload and never changes live state', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    state.completed.add(canonLessonMarker('B02', state.day));
    final before = state.toJson();

    expect(
      () => submission(
        state,
        'B02',
        practice: true,
        split: [-1, 0, 0],
      ).apply(state),
      throwsA(isA<GameRule>()),
    );
    expect(state.toJson(), before);

    expect(
      submission(
        state,
        'B02',
        practice: true,
        split: [15, 10, 15],
      ).apply(state),
      0,
    );
    expect(state.toJson(), before);
  });

  test('P01 requires the exact care basket and awards no basket charge', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final before = state.toJson();
    final wrong = submission(
      state,
      'P01',
      basketIds: ['food_refill', 'ball'],
      rationale: 'Корм и чистота нужны питомцу сегодня',
    );
    expect(() => wrong.apply(state), throwsA(isA<GameRule>()));
    expect(state.toJson(), before);

    final reward = submission(
      state,
      'P01',
      basketIds: ['food_refill', 'clean_care'],
      rationale: 'Корм и чистота нужны питомцу сегодня',
    ).apply(state);
    expect(reward, 30);
    expect(state.wallet, [130, 0, 0]);
    expect(state.purchased, isEmpty);
    expect(state.completed, contains('canon:P01:1'));
  });

  test('P01 shares the period income ceiling with household work', () {
    final state = GameState()..confirmPlan([15, 10, 15]);
    final job = householdJobForPeriod(state.day);
    state.setCurrentRoom(job.room);
    expect(state.finishJob(job.id, period: state.day), 30);
    final walletAfterJob = List<int>.from(state.wallet);

    final reward = submission(
      state,
      'P01',
      basketIds: ['food_refill', 'clean_care'],
      rationale: 'Корм и чистота нужны питомцу сегодня',
    ).apply(state);

    expect(reward, 0);
    expect(state.wallet, walletAfterJob);
    expect(state.completed, contains('canon:P01:1'));
  });

  test('P06 validates real shortage evidence and never spends', () {
    final state = GameState()..wallet = [30, 20, 10];
    final before = state.toJson();

    expect(
      () => submission(
        state,
        'P06',
        purchaseAttempted: true,
        p06Resolution: 'defer',
        attemptedAvailable: 30,
        attemptedPrice: 34,
      ).apply(state),
      throwsA(isA<GameRule>()),
    );
    expect(state.toJson(), before);

    expect(
      submission(
        state,
        'P06',
        purchaseAttempted: true,
        p06Resolution: 'defer',
        attemptedAvailable: 30,
        attemptedPrice: 35,
      ).apply(state),
      0,
    );
    expect(state.wallet, [30, 20, 10]);
    expect(state.purchased, isEmpty);
  });

  test('P06 rich balance requires an explicit 30 versus 35 teaching copy', () {
    final state = GameState();
    final beforeWallet = List<int>.from(state.wallet);

    expect(
      () => submission(
        state,
        'P06',
        purchaseAttempted: true,
        p06Resolution: 'replan',
        attemptedAvailable: 100,
        attemptedPrice: 35,
      ).apply(state),
      throwsA(isA<GameRule>()),
    );

    expect(
      submission(
        state,
        'P06',
        purchaseAttempted: true,
        p06Resolution: 'replan',
        attemptedAvailable: 30,
        attemptedPrice: 35,
        useTeachingCopy: true,
      ).apply(state),
      0,
    );
    expect(state.wallet, beforeWallet);
  });

  test('submission list fields are immutable', () {
    final state = GameState();
    final command = submission(state, 'B02', split: [15, 10, 15]);

    expect(() => command.snapshotWallet[0] = 0, throwsUnsupportedError);
    expect(() => command.snapshotPlan.add(1), throwsUnsupportedError);
    expect(() => command.split![0] = 0, throwsUnsupportedError);
    expect(() => command.basketIds.add('ball'), throwsUnsupportedError);
  });
}
