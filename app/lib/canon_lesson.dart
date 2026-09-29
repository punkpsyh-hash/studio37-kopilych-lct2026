import 'content.dart';
import 'game.dart';
import 'story.dart';

const canonLessonIds = {'B02', 'B04', 'S01', 'S02', 'P01', 'P06'};

bool isCanonicalLesson(String id) => canonLessonIds.contains(id);

String canonLessonMarker(String lessonId, int day) => 'canon:$lessonId:$day';

/// Values captured inside the save transaction, detached from mutable profiles.
class CanonLessonSnapshot {
  CanonLessonSnapshot(GameState state)
    : wallet = List<int>.unmodifiable(state.wallet),
      needs = List<int>.unmodifiable(state.needs),
      goalId = state.goalId,
      planConfirmed = state.planConfirmed;

  final List<int> wallet, needs;
  final String goalId;
  final bool planConfirmed;
  int get total => wallet.fold(0, (sum, value) => sum + value);
}

/// Publish only after persistence succeeds; creating this never applies a lesson.
class CanonLessonReceipt {
  CanonLessonReceipt({
    required this.submission,
    required this.reward,
    required this.applied,
    required this.before,
    required GameState after,
  }) : after = CanonLessonSnapshot(after),
       nextTarget = !after.planConfirmed
           ? 'B02'
           : storyActiveTask(after)?.target ?? 'home',
       nextLabel = !after.planConfirmed
           ? 'Составить исходный план'
           : storyActiveTask(after)?.label ?? 'Вернуться к другу';

  final CanonLessonSubmission submission;
  final int reward;
  final bool applied;
  final CanonLessonSnapshot before, after;
  final String nextTarget, nextLabel;
  bool get practice => submission.practice;
}

/// Immutable command produced by a canonical lesson screen.
///
/// The screen works with a deep copy. Only [apply] may change the live state,
/// after it has rejected stale input and validated the complete payload.
class CanonLessonSubmission {
  CanonLessonSubmission({
    required this.lessonId,
    required this.snapshotDay,
    required List<int> snapshotWallet,
    required List<int> snapshotPlan,
    required this.snapshotPlanConfirmed,
    required List<String> snapshotPlanVersionSignatures,
    required this.snapshotGoalId,
    required this.practice,
    List<int>? split,
    this.reason,
    this.goalId,
    this.transferTarget,
    this.amount,
    List<String> basketIds = const [],
    this.rationale,
    this.purchaseAttempted = false,
    this.p06Resolution,
    this.attemptedAvailable,
    this.attemptedPrice,
    this.useTeachingCopy = false,
  }) : snapshotWallet = List<int>.unmodifiable(snapshotWallet),
       snapshotPlan = List<int>.unmodifiable(snapshotPlan),
       snapshotPlanVersionSignatures = List<String>.unmodifiable(
         snapshotPlanVersionSignatures,
       ),
       split = split == null ? null : List<int>.unmodifiable(split),
       basketIds = List<String>.unmodifiable(basketIds);

  factory CanonLessonSubmission.capture(
    GameState snapshot, {
    required String lessonId,
    required bool practice,
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
  }) => CanonLessonSubmission(
    lessonId: lessonId,
    snapshotDay: snapshot.day,
    snapshotWallet: snapshot.wallet,
    snapshotPlan: snapshot.plan,
    snapshotPlanConfirmed: snapshot.planConfirmed,
    snapshotPlanVersionSignatures: _planSignatures(snapshot),
    snapshotGoalId: snapshot.goalId,
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

  final String lessonId;
  final int snapshotDay;
  final List<int> snapshotWallet;
  final List<int> snapshotPlan;
  final bool snapshotPlanConfirmed;
  final List<String> snapshotPlanVersionSignatures;
  final String snapshotGoalId;
  final bool practice;

  final List<int>? split;
  final String? reason;
  final String? goalId;
  final String? transferTarget;
  final int? amount;
  final List<String> basketIds;
  final String? rationale;
  final bool purchaseAttempted;
  final String? p06Resolution;
  final int? attemptedAvailable;
  final int? attemptedPrice;
  final bool useTeachingCopy;

  /// Applies one atomic canonical action to the live state.
  ///
  /// A retry of a completed command is accepted before stale-snapshot checks,
  /// so a persisted response lost by the caller cannot duplicate an action.
  int apply(GameState live) {
    if (!canonLessonIds.contains(lessonId)) {
      throw const GameRule('Неизвестное обязательное задание.');
    }
    final marker = canonLessonMarker(lessonId, snapshotDay);
    if (live.completed.contains(marker) && !practice) return 0;

    _validateSnapshot(live);
    if (practice) {
      final copy = GameState.fromJson(live.toJson());
      _execute(copy);
      return 0;
    }

    final reward = _execute(live);

    live.completed.add(lessonId);
    live.completed.add(marker);
    return reward;
  }

  int _execute(GameState state) => switch (lessonId) {
    'B02' => _applyBaseline(state),
    'B04' => _applyRevision(state),
    'S01' => _applyGoal(state),
    'S02' => _applyTransfer(state),
    'P01' => _applyBasket(state),
    'P06' => _applyInsufficientWant(),
    _ => throw const GameRule('Неизвестное обязательное задание.'),
  };

  void _validateSnapshot(GameState live) {
    if (live.day != snapshotDay) {
      throw const GameRule(
        'Начался другой игровой день. Открой задание ещё раз.',
      );
    }
    if (!_sameInts(live.wallet, snapshotWallet)) {
      throw const GameRule(
        'Баланс уже изменился. Проверь новые суммы и повтори решение.',
      );
    }
    if ({'B02', 'B04', 'P01'}.contains(lessonId) &&
        (!_sameInts(live.plan, snapshotPlan) ||
            live.planConfirmed != snapshotPlanConfirmed ||
            !_sameStrings(
              _planSignatures(live),
              snapshotPlanVersionSignatures,
            ))) {
      throw const GameRule(
        'План уже изменился. Открой задание ещё раз и проверь его.',
      );
    }
    if ({'S01', 'S02'}.contains(lessonId) && live.goalId != snapshotGoalId) {
      throw const GameRule('Цель уже изменилась. Сравни мечты ещё раз.');
    }
  }

  int _applyBaseline(GameState live) {
    final value = split;
    if (value == null) {
      throw const GameRule('Распредели монеты по трём направлениям.');
    }
    if (snapshotPlanConfirmed) {
      final baseline = live.planVersions.first.split;
      if (!_sameInts(value, baseline)) {
        throw const GameRule(
          'Исходный план уже сохранён. Для новых сумм открой изменение плана.',
        );
      }
      return 0;
    }
    live.confirmPlan(value);
    return 0;
  }

  int _applyRevision(GameState live) {
    final value = split;
    final explanation = reason?.trim();
    if (!snapshotPlanConfirmed || snapshotPlanVersionSignatures.isEmpty) {
      throw const GameRule('Сначала сохрани исходный план.');
    }
    if (value == null || _sameInts(value, snapshotPlan)) {
      throw const GameRule('Измени хотя бы одну сумму в плане.');
    }
    const allowedReasons = {
      'После дохода уточняю суммы',
      'Откладываю желание и направляю деньги важнее',
    };
    if (!allowedReasons.contains(explanation)) {
      throw const GameRule('Выбери честную причину изменения плана.');
    }
    if (explanation == 'После дохода уточняю суммы' &&
        live.periodActivity.income <= 0) {
      throw const GameRule(
        'Доход ещё не получен. Выбери другую причину или вернись после дохода.',
      );
    }
    live.confirmPlan(value, reason: explanation);
    return 0;
  }

  int _applyGoal(GameState live) {
    final selected = goalId;
    if (selected == null || !goals.any((goal) => goal.id == selected)) {
      throw const GameRule('Сначала выбери одну из трёх мечт.');
    }
    live.goalId = selected;
    return 0;
  }

  int _applyTransfer(GameState live) {
    final target = switch (transferTarget) {
      'dream' => 1,
      'reserve' => 2,
      _ => -1,
    };
    final value = amount;
    if (target < 0 || value == null || value <= 0) {
      throw const GameRule('Выбери конверт и целую сумму больше нуля.');
    }
    live.transfer(0, target, value);
    return 0;
  }

  int _applyBasket(GameState live) {
    const requiredBasket = ['food_refill', 'clean_care'];
    if (!_sameStrings(basketIds, requiredBasket)) {
      throw const GameRule(
        'В учебной корзине нужны корм за 10 и чистота за 5.',
      );
    }
    if (rationale != 'Корм и чистота нужны питомцу сегодня') {
      throw const GameRule('Объясни, почему необходимое выбирают первым.');
    }
    final mission = canonicalMissions.firstWhere(
      (mission) => mission.id == 'P01',
    );
    return live.finish(
      mission,
      mission.correct,
      DateTime.now(),
      withoutHint: true,
    );
  }

  int _applyInsufficientWant() {
    if (!purchaseAttempted) {
      throw const GameRule('Сначала попробуй купить лежанку и посмотри итог.');
    }
    if (p06Resolution != 'defer' && p06Resolution != 'replan') {
      throw const GameRule('Выбери отсрочку или перепланирование.');
    }
    const price = 35;
    final expectedTeachingCopy = snapshotWallet[0] >= price;
    final expectedAvailable = expectedTeachingCopy ? 30 : snapshotWallet[0];
    if (attemptedPrice != price ||
        useTeachingCopy != expectedTeachingCopy ||
        attemptedAvailable != expectedAvailable ||
        price - expectedAvailable <= 0) {
      throw const GameRule(
        'Проверь цену лежанки и доступную сумму перед решением.',
      );
    }
    return 0;
  }
}

List<String> _planSignatures(GameState state) => [
  for (final version in state.planVersions)
    '${version.split.length}:${version.split.join(',')}:${version.reason}',
];

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
