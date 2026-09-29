import 'dart:math';
import 'content.dart';

const envelopeNames = ['Сейчас', 'На мечту', 'Запас'];
const speciesNames = ['Котёнок', 'Щенок', 'Хомячок'];
const defaultNames = ['Персик', 'Бублик', 'Плюш'];
const graphicsQualityModes = ['auto', 'low', 'standard', 'high'];

String normalizedGraphicsQuality(Object? value) =>
    value is String && graphicsQualityModes.contains(value) ? value : 'auto';

class HouseholdJob {
  const HouseholdJob(this.id, this.title, this.room, this.totalSteps);
  final String id, title, room;
  final int totalSteps;
}

const householdJobs = <String, HouseholdJob>{
  'J01': HouseholdJob('J01', 'Чистая посуда', 'kitchen', 8),
  'J02': HouseholdJob('J02', 'Всё на месте', 'living', 3),
  'J03': HouseholdJob('J03', 'Полотенца по местам', 'bathroom', 4),
  'J04': HouseholdJob('J04', 'Разбираем упаковки', 'kitchen', 4),
  'J05': HouseholdJob('J05', 'Полки к новоселью', 'living', 4),
  'J06': HouseholdJob('J06', 'Подметём вместе', 'living', 6),
};

HouseholdJob householdJobForPeriod(int period) =>
    householdJobs['J${period.clamp(1, 6).toString().padLeft(2, '0')}']!;

class Dream {
  const Dream(this.id, this.name, this.description, this.price);
  final String id, name, description;
  final int price;
}

/// Позиция каталога покупок (§2.5.6 ТЗ).
class CatalogItem {
  const CatalogItem(
    this.id,
    this.name,
    this.description,
    this.price,
    this.required, {
    this.need = -1,
    this.needBoost = 0,
    this.roomItem = false,
  });
  final String id, name, description;
  final int price;

  /// Обязательная покупка (нужда питомца) или необязательное желание.
  final bool required;

  /// Индекс потребности, которую закрывает предмет (-1 — не влияет).
  final int need, needBoost;

  /// Предмет появляется в комнате питомца.
  final bool roomItem;
}

class GlossaryTerm {
  const GlossaryTerm(this.term, this.definition);
  final String term, definition;
}

class GameRule implements Exception {
  const GameRule(this.message);
  final String message;
  @override
  String toString() => message;
}

const financeCategories = {'mandatory', 'wants', 'savings', 'income'};
const financeKinds = {
  'care',
  'purchase',
  'transfer',
  'goal_purchase',
  'reward',
};

class PlanVersion {
  const PlanVersion(this.split, this.reason);
  final List<int> split;
  final String reason;

  Map<String, dynamic> toJson() => {'split': split, 'reason': reason};

  factory PlanVersion.fromJson(Map<String, dynamic> j) =>
      PlanVersion(List<int>.from(j['split'] as List), j['reason'] as String);
}

/// Typed metadata persisted beside the atomic SQLite operation.
class FinanceMutation {
  const FinanceMutation({
    required this.kind,
    required this.category,
    required this.amount,
    this.fromWallet,
    this.toWallet,
    this.period,
  });
  final String kind, category;
  final int amount;
  final int? fromWallet, toWallet;
  final int? period;
}

class PeriodActivity {
  const PeriodActivity({
    this.known = true,
    this.mandatorySpent = 0,
    this.wantsSpent = 0,
    this.savingsDeposits = 0,
    this.savingsWithdrawals = 0,
    this.goalSpent = 0,
    this.income = 0,
  });

  final bool known;
  final int mandatorySpent, wantsSpent;
  final int savingsDeposits, savingsWithdrawals;
  final int goalSpent;
  final int income;
  int get netSavings => savingsDeposits - savingsWithdrawals;

  PeriodActivity add(FinanceMutation mutation) => PeriodActivity(
    known: known,
    mandatorySpent:
        mandatorySpent +
        (mutation.category == 'mandatory' ? mutation.amount : 0),
    wantsSpent:
        wantsSpent +
        (mutation.category == 'wants' && mutation.fromWallet == 0
            ? mutation.amount
            : 0),
    savingsDeposits:
        savingsDeposits +
        (mutation.category == 'savings' && mutation.fromWallet == 0
            ? mutation.amount
            : 0),
    savingsWithdrawals:
        savingsWithdrawals +
        (mutation.category == 'savings' && mutation.toWallet == 0
            ? mutation.amount
            : 0),
    goalSpent:
        goalSpent + (mutation.kind == 'goal_purchase' ? mutation.amount : 0),
    income: income + (mutation.category == 'income' ? mutation.amount : 0),
  );

  Map<String, dynamic> toJson() => {
    'known': known,
    'mandatorySpent': mandatorySpent,
    'wantsSpent': wantsSpent,
    'savingsDeposits': savingsDeposits,
    'savingsWithdrawals': savingsWithdrawals,
    'goalSpent': goalSpent,
    'income': income,
  };

  factory PeriodActivity.fromJson(Map<String, dynamic> j) {
    final complete = [
      'mandatorySpent',
      'wantsSpent',
      'savingsDeposits',
      'savingsWithdrawals',
      'goalSpent',
      'income',
    ].every((key) => j[key] is int);
    return PeriodActivity(
      known: (j['known'] as bool? ?? false) && complete,
      mandatorySpent: j['mandatorySpent'] as int? ?? 0,
      wantsSpent: j['wantsSpent'] as int? ?? 0,
      savingsDeposits: j['savingsDeposits'] as int? ?? 0,
      savingsWithdrawals: j['savingsWithdrawals'] as int? ?? 0,
      goalSpent: j['goalSpent'] as int? ?? 0,
      income: j['income'] as int? ?? 0,
    );
  }
}

/// Итог одного игрового периода: подтверждённый план и факт на конец дня.
class DayFact {
  const DayFact(
    this.day,
    this.plan,
    this.wallet,
    this.caredAll, {
    this.planVersions = const [],
    this.mandatorySpent,
    this.wantsSpent,
    this.savingsDeposits,
    this.savingsWithdrawals,
    this.goalSpent,
    this.income,
    this.planFactReviewed = false,
    this.planFactExplanation,
    this.synthetic = false,
  });
  final int day;
  final List<int> plan;
  final List<int> wallet;
  final bool caredAll;
  final List<PlanVersion> planVersions;
  final int? mandatorySpent, wantsSpent;
  final int? savingsDeposits, savingsWithdrawals;
  final int? goalSpent;
  final int? income;
  final bool planFactReviewed;
  final String? planFactExplanation;
  final bool synthetic;

  bool get factKnown =>
      mandatorySpent != null &&
      wantsSpent != null &&
      savingsDeposits != null &&
      savingsWithdrawals != null &&
      goalSpent != null &&
      income != null;
  int? get netSavings =>
      factKnown ? savingsDeposits! - savingsWithdrawals! : null;
  List<int> get baselinePlan =>
      planVersions.isEmpty ? plan : planVersions.first.split;
  List<int> get revisedPlan =>
      planVersions.isEmpty ? plan : planVersions.last.split;
  bool get hasPlanDeviation =>
      factKnown &&
      (revisedPlan[0] != mandatorySpent ||
          revisedPlan[1] != wantsSpent ||
          revisedPlan[2] != netSavings);
  bool get qualifiesForGrowth =>
      !synthetic &&
      caredAll &&
      planFactReviewed &&
      (netSavings ?? 0) > 0 &&
      (!hasPlanDeviation ||
          (planFactExplanation != null &&
              planFactExplanation!.trim().isNotEmpty));

  Map<String, dynamic> toJson() => {
    'day': day,
    'plan': plan,
    'wallet': wallet,
    'cared': caredAll,
    'planVersions': planVersions.map((v) => v.toJson()).toList(),
    'mandatorySpent': mandatorySpent,
    'wantsSpent': wantsSpent,
    'savingsDeposits': savingsDeposits,
    'savingsWithdrawals': savingsWithdrawals,
    'goalSpent': goalSpent,
    'income': income,
    'planFactReviewed': planFactReviewed,
    'planFactExplanation': planFactExplanation,
    'synthetic': synthetic,
  };

  factory DayFact.fromJson(Map<String, dynamic> j) => DayFact(
    j['day'] as int,
    List<int>.from(j['plan'] as List),
    List<int>.from(j['wallet'] as List),
    j['cared'] as bool? ?? false,
    planVersions: (j['planVersions'] as List? ?? [])
        .map((v) => PlanVersion.fromJson(v as Map<String, dynamic>))
        .toList(),
    mandatorySpent: j['mandatorySpent'] as int?,
    wantsSpent: j['wantsSpent'] as int?,
    savingsDeposits: j['savingsDeposits'] as int?,
    savingsWithdrawals: j['savingsWithdrawals'] as int?,
    goalSpent: j['goalSpent'] as int?,
    income: j['income'] as int?,
    planFactReviewed: j['planFactReviewed'] as bool? ?? false,
    planFactExplanation: j['planFactExplanation'] as String?,
    synthetic: j['synthetic'] as bool? ?? false,
  );
}

class GameState {
  GameState();
  String? name;
  int species = 0, color = 0, accessory = 0;
  String currentRoom = 'living';
  bool lampOn = true;
  bool kitchenLampOn = true, bathroomLampOn = true;
  bool starsOn = true, nightlightOn = true;
  List<int> wallet = [100, 0, 0];
  List<int> needs = [60, 65, 55];
  int day = 1;
  int incomeClaimedDay = 0;
  String goalId = 'house';
  Set<String> owned = {}, completed = {}, independent = {}, rewards = {};
  Set<int> cared = {};
  Set<String> storyMarks = {};
  Set<String> purchased = {};
  String? equippedWearable;
  int careDays = 0;
  int achievedStage = 1;
  int qualifyingPeriods = 0;
  String maxDate = '';

  /// Real dates are independent of the manually advanced learning period.
  String adoptedOn = '';
  String lastLoginDate = '';
  int needsUpdatedAtMs = 0;
  bool reducedMotion = false;
  bool soundEnabled = true;
  int soundVolume = 100;
  bool voiceEnabled = true;
  bool musicEnabled = true;
  int musicVolume = 35;
  String graphicsQuality = 'auto';

  /// План текущего дня: [на обязательное, на желания, на накопления].
  List<int> plan = [0, 0, 0];
  bool planConfirmed = false;
  int plansConfirmed = 0;
  List<PlanVersion> planVersions = [];
  PeriodActivity periodActivity = const PeriodActivity();
  List<DayFact> facts = [];
  final List<FinanceMutation> _pendingFinance = [];
  bool _snapshotReplacement = false;

  /// Демонстрационный профиль с готовыми пятью периодами (§2.5.13).
  bool demoMode = false;

  int get total => wallet.reduce((a, b) => a + b);
  bool get incomeAvailable => incomeClaimedDay != day;
  Dream get goal => goals.firstWhere((g) => g.id == goalId);
  int get stage => achievedStage;
  bool get stageTwo => achievedStage >= 2;
  bool get _qualifiesStageTwo => qualifyingPeriods >= 3;
  bool get _qualifiesStageThree => qualifyingPeriods >= 5;
  String get stageName =>
      ['Новый друг', 'Верный помощник', 'Хранитель мечты'][stage - 1];

  Map<String, dynamic> toJson() => {
    'schema': 9,
    'name': name,
    'species': species,
    'color': color,
    'accessory': accessory,
    'currentRoom': currentRoom,
    'lampOn': lampOn,
    'kitchenLampOn': kitchenLampOn,
    'bathroomLampOn': bathroomLampOn,
    'starsOn': starsOn,
    'nightlightOn': nightlightOn,
    'wallet': wallet,
    'needs': needs,
    'day': day,
    'incomeClaimedDay': incomeClaimedDay,
    'goal': goalId,
    'owned': owned.toList(),
    'completed': completed.toList(),
    'independent': independent.toList(),
    'rewards': rewards.toList(),
    'cared': cared.toList(),
    'storyMarks': storyMarks.toList(),
    'purchased': purchased.toList(),
    'equippedWearable': equippedWearable,
    'careDays': careDays,
    'achievedStage': achievedStage,
    'qualifyingPeriods': qualifyingPeriods,
    'maxDate': maxDate,
    'adoptedOn': adoptedOn,
    'lastLoginDate': lastLoginDate,
    'needsUpdatedAtMs': needsUpdatedAtMs,
    'reducedMotion': reducedMotion,
    'soundEnabled': soundEnabled,
    'soundVolume': soundVolume,
    'voiceEnabled': voiceEnabled,
    'musicEnabled': musicEnabled,
    'musicVolume': musicVolume,
    'graphicsQuality': graphicsQuality,
    'plan': plan,
    'planConfirmed': planConfirmed,
    'plansConfirmed': plansConfirmed,
    'planVersions': planVersions.map((v) => v.toJson()).toList(),
    'periodActivity': periodActivity.toJson(),
    'facts': facts.map((f) => f.toJson()).toList(),
    'demoMode': demoMode,
  };

  factory GameState.fromJson(Map<String, dynamic> j) {
    final schema = j['schema'] as int;
    if (schema < 1 || schema > 9) {
      throw const FormatException('Неизвестная версия сохранения');
    }
    final s = GameState()
      ..name = j['name'] as String?
      ..species = j['species'] as int
      ..color = j['color'] as int
      ..accessory = j['accessory'] as int
      ..currentRoom = j['currentRoom'] as String? ?? 'living'
      ..lampOn = j['lampOn'] as bool? ?? true
      ..kitchenLampOn = j['kitchenLampOn'] as bool? ?? true
      ..bathroomLampOn = j['bathroomLampOn'] as bool? ?? true
      ..starsOn = j['starsOn'] as bool? ?? true
      ..nightlightOn = j['nightlightOn'] as bool? ?? true
      ..wallet = List<int>.from(j['wallet'] as List)
      ..needs = List<int>.from(j['needs'] as List)
      ..day = j['day'] as int
      ..incomeClaimedDay = j['incomeClaimedDay'] as int? ?? 0
      ..goalId = j['goal'] as String
      ..owned = Set<String>.from(j['owned'] as List)
      ..completed = Set<String>.from(j['completed'] as List)
      ..rewards = Set<String>.from(j['rewards'] as List)
      ..independent = Set<String>.from(j['independent'] as List? ?? [])
      ..cared = Set<int>.from(j['cared'] as List? ?? [])
      ..storyMarks = Set<String>.from(j['storyMarks'] as List? ?? [])
      ..purchased = {
        for (final id in List<String>.from(j['purchased'] as List? ?? []))
          switch (id) {
            'food' => 'food_refill',
            'shampoo' => 'clean_care',
            _ => id,
          },
      }
      ..equippedWearable = schema < 5
          ? ((j['purchased'] as List? ?? []).contains('cap') ? 'cap' : null)
          : j['equippedWearable'] as String?
      ..careDays = j['careDays'] as int? ?? 0
      ..achievedStage = schema < 6 ? 1 : j['achievedStage'] as int? ?? 1
      ..qualifyingPeriods = schema < 8 ? 0 : j['qualifyingPeriods'] as int
      ..maxDate = j['maxDate'] as String? ?? ''
      ..adoptedOn = j['adoptedOn'] as String? ?? ''
      ..lastLoginDate = j['lastLoginDate'] as String? ?? ''
      ..needsUpdatedAtMs = j['needsUpdatedAtMs'] as int? ?? 0
      ..reducedMotion = j['reducedMotion'] as bool? ?? false
      ..soundEnabled = j['soundEnabled'] as bool? ?? true
      ..soundVolume = switch (j['soundVolume']) {
        int value when value < 0 => 0,
        int value when value > 100 => 100,
        int value => value,
        _ => 100,
      }
      ..voiceEnabled = j['voiceEnabled'] as bool? ?? true
      ..musicEnabled = j['musicEnabled'] as bool? ?? true
      ..musicVolume = switch (j['musicVolume']) {
        int value when value < 0 => 0,
        int value when value > 100 => 100,
        int value => value,
        _ => 35,
      }
      ..graphicsQuality = normalizedGraphicsQuality(j['graphicsQuality'])
      ..plan = j['plan'] == null ? [0, 0, 0] : List<int>.from(j['plan'] as List)
      ..planConfirmed = j['planConfirmed'] as bool? ?? false
      ..plansConfirmed = j['plansConfirmed'] as int? ?? 0
      ..planVersions = schema < 6
          ? ((j['planConfirmed'] as bool? ?? false)
                ? [
                    PlanVersion(
                      List<int>.from(j['plan'] as List? ?? [0, 0, 0]),
                      'legacy_baseline',
                    ),
                  ]
                : [])
          : (j['planVersions'] as List? ?? [])
                .map((v) => PlanVersion.fromJson(v as Map<String, dynamic>))
                .toList()
      ..periodActivity = schema < 6
          ? const PeriodActivity(known: false)
          : PeriodActivity.fromJson(
              j['periodActivity'] as Map<String, dynamic>? ??
                  <String, dynamic>{},
            )
      ..facts = j['facts'] == null
          ? []
          : (j['facts'] as List).map((f) {
              final fact = Map<String, dynamic>.from(f as Map<String, dynamic>);
              if (schema < 8) {
                fact.remove('planFactReviewed');
                fact.remove('planFactExplanation');
              }
              return DayFact.fromJson(fact);
            }).toList()
      ..demoMode = j['demoMode'] as bool? ?? false;
    if (schema < 7) {
      // Existing money is never removed. Unknown legacy periods start the new
      // earning rule next period; known v6 income consumes this period's slot.
      s.incomeClaimedDay =
          !s.periodActivity.known || s.periodActivity.income > 0 ? s.day : 0;
    }
    if (schema < 3) {
      if (s.wallet[1] > 0 || s.owned.isNotEmpty) s.storyMarks.add('saved');
      if (s.wallet[2] > 0) s.storyMarks.add('reserve');
    }
    if (schema < 6) {
      final legacyStageTwo =
          s.completed.contains('M01') &&
          s.completed.any((mission) => {'M10', 'M12'}.contains(mission)) &&
          s.careDays > 0 &&
          s.plansConfirmed > 0;
      s.achievedStage = legacyStageTwo
          ? (s.owned.isNotEmpty && s.independent.contains('M12') ? 3 : 2)
          : 1;
    } else {
      s._promoteStage();
    }
    s.validate();
    return s;
  }

  void validate() {
    bool invalidFact(DayFact fact) {
      final details = [
        fact.mandatorySpent,
        fact.wantsSpent,
        fact.savingsDeposits,
        fact.savingsWithdrawals,
        fact.goalSpent,
        fact.income,
      ];
      return fact.plan.length != 3 ||
          fact.wallet.length != 3 ||
          fact.planVersions.any(
            (version) =>
                version.split.length != 3 ||
                version.split.any(
                  (amount) => amount < 0 || amount > 100000000,
                ) ||
                version.reason.trim().isEmpty,
          ) ||
          (fact.planFactExplanation != null &&
              fact.planFactExplanation!.trim().isEmpty) ||
          (fact.planFactReviewed &&
              fact.hasPlanDeviation &&
              fact.planFactExplanation == null) ||
          details.whereType<int>().any((amount) => amount < 0) ||
          (details.any((value) => value != null) && !fact.factKnown);
    }

    if (wallet.length != 3 ||
        wallet.any((v) => v < 0 || v > 100000000) ||
        needs.length != 3 ||
        needs.any((v) => v < 0 || v > 100) ||
        plan.length != 3 ||
        plan.any((v) => v < 0 || v > 100000000) ||
        species < 0 ||
        species > 2 ||
        color < 0 ||
        color > 5 ||
        accessory < 0 ||
        accessory > 2 ||
        !{'living', 'kitchen', 'bathroom'}.contains(currentRoom) ||
        day < 1 ||
        incomeClaimedDay < 0 ||
        incomeClaimedDay > day ||
        careDays < 0 ||
        achievedStage < 1 ||
        achievedStage > 3 ||
        qualifyingPeriods < 0 ||
        qualifyingPeriods > 100000000 ||
        soundVolume < 0 ||
        soundVolume > 100 ||
        musicVolume < 0 ||
        musicVolume > 100 ||
        !graphicsQualityModes.contains(graphicsQuality) ||
        !_isCanonicalDateKey(maxDate) ||
        !_isCanonicalDateKey(adoptedOn) ||
        !_isCanonicalDateKey(lastLoginDate) ||
        needsUpdatedAtMs < 0 ||
        plansConfirmed < 0 ||
        cared.any((v) => v < 0 || v > 2) ||
        storyMarks.any((v) => !['saved', 'reserve'].contains(v)) ||
        !goals.any((g) => g.id == goalId) ||
        owned.any((id) => !goals.any((g) => g.id == id)) ||
        purchased.any(
          (id) =>
              !catalogItems.any((i) => i.id == id) &&
              !{'leash', 'vitamins'}.contains(id),
        ) ||
        (equippedWearable != null &&
            (!{'cap', 'bow'}.contains(equippedWearable) ||
                !purchased.contains(equippedWearable))) ||
        planVersions.any(
          (v) =>
              v.split.length != 3 ||
              v.split.any((amount) => amount < 0 || amount > 100000000) ||
              v.reason.trim().isEmpty,
        ) ||
        (planConfirmed != planVersions.isNotEmpty) ||
        facts.any(invalidFact) ||
        [
          periodActivity.mandatorySpent,
          periodActivity.wantsSpent,
          periodActivity.savingsDeposits,
          periodActivity.savingsWithdrawals,
          periodActivity.goalSpent,
          periodActivity.income,
        ].any((amount) => amount < 0) ||
        (name != null && (name!.trim().isEmpty || name!.length > 24))) {
      throw const FormatException('Сохранение содержит неверные значения');
    }
  }

  List<FinanceMutation> takePendingFinanceMutations() {
    final result = List<FinanceMutation>.from(_pendingFinance);
    _pendingFinance.clear();
    return result;
  }

  bool takeSnapshotReplacement() {
    final result = _snapshotReplacement;
    _snapshotReplacement = false;
    return result;
  }

  void markPeriodActivityUnknown() {
    periodActivity = PeriodActivity(
      known: false,
      mandatorySpent: periodActivity.mandatorySpent,
      wantsSpent: periodActivity.wantsSpent,
      savingsDeposits: periodActivity.savingsDeposits,
      savingsWithdrawals: periodActivity.savingsWithdrawals,
      goalSpent: periodActivity.goalSpent,
      income: periodActivity.income,
    );
  }

  void _recordFinance(FinanceMutation mutation) {
    final dated = FinanceMutation(
      kind: mutation.kind,
      category: mutation.category,
      amount: mutation.amount,
      fromWallet: mutation.fromWallet,
      toWallet: mutation.toWallet,
      period: day,
    );
    _pendingFinance.add(dated);
    periodActivity = periodActivity.add(dated);
  }

  void _promoteStage() {
    if (_qualifiesStageThree) {
      achievedStage = max(achievedStage, 3);
    } else if (_qualifiesStageTwo) {
      achievedStage = max(achievedStage, 2);
    }
  }

  void setCurrentRoom(String room) {
    if (!{'living', 'kitchen', 'bathroom'}.contains(room)) {
      throw const GameRule('Неизвестная комната.');
    }
    currentRoom = room;
  }

  /// Legacy profiles start their real-time clock on first resume, so an old
  /// save never loses needs or money merely because it was migrated.
  void markAdopted(DateTime now) {
    adoptedOn = adoptedOn.isEmpty ? dateKey(now) : adoptedOn;
    lastLoginDate = lastLoginDate.isEmpty ? dateKey(now) : lastLoginDate;
    if (needsUpdatedAtMs == 0) needsUpdatedAtMs = now.millisecondsSinceEpoch;
  }

  bool needsResume(DateTime now) {
    if (name == null) return false;
    final today = dateKey(now);
    return adoptedOn.isEmpty ||
        lastLoginDate.isEmpty ||
        today.compareTo(lastLoginDate) > 0 ||
        needsUpdatedAtMs == 0 ||
        now.millisecondsSinceEpoch - needsUpdatedAtMs >= 288000;
  }

  /// One need point every 4.8 minutes: a full meter lasts eight real hours.
  /// Clock rollback never restores needs or permits a duplicate login bonus.
  void resume(DateTime now) {
    if (name == null) return;
    final today = dateKey(now);
    if (adoptedOn.isEmpty) adoptedOn = today;
    if (lastLoginDate.isEmpty) lastLoginDate = today;
    final nowMs = now.millisecondsSinceEpoch;
    if (needsUpdatedAtMs == 0) needsUpdatedAtMs = nowMs;
    if (nowMs > needsUpdatedAtMs) {
      final loss = (nowMs - needsUpdatedAtMs) ~/ 288000;
      if (loss > 0) {
        needs = [for (final need in needs) max(0, need - loss)];
        needsUpdatedAtMs += loss * 288000;
      }
    }
    if (today.compareTo(lastLoginDate) > 0) {
      lastLoginDate = today;
      wallet[0] += 10;
      _recordFinance(
        const FinanceMutation(
          kind: 'reward',
          category: 'income',
          amount: 10,
          toWallet: 0,
        ),
      );
    }
  }

  bool get currentLampOn => switch (currentRoom) {
    'kitchen' => kitchenLampOn,
    'bathroom' => bathroomLampOn,
    _ => lampOn,
  };

  void toggleLamp() {
    switch (currentRoom) {
      case 'kitchen':
        kitchenLampOn = !kitchenLampOn;
      case 'bathroom':
        bathroomLampOn = !bathroomLampOn;
      default:
        lampOn = !lampOn;
    }
  }

  void toggleOptionalFixture(String fixture) {
    if (fixture == 'stars' && owned.contains('stars')) {
      starsOn = !starsOn;
    } else if (fixture == 'nightlight' && purchased.contains('nightlight')) {
      nightlightOn = !nightlightOn;
    } else {
      throw const GameRule('Сначала добавим этот светильник в дом.');
    }
  }

  void transfer(int from, int to, int amount) {
    if (from < 0 || from > 2 || to < 0 || to > 2 || from == to || amount <= 0) {
      throw const GameRule('Выбери разные конверты и целую сумму больше нуля.');
    }
    if (wallet[from] < amount) {
      throw GameRule(
        'В конверте «${envelopeNames[from]}» только ${wallet[from]} монет.',
      );
    }
    wallet[from] -= amount;
    wallet[to] += amount;
    _recordFinance(
      FinanceMutation(
        kind: 'transfer',
        category: 'savings',
        amount: amount,
        fromWallet: from,
        toWallet: to,
      ),
    );
    if (to == 1) storyMarks.add('saved');
    if (to == 2) storyMarks.add('reserve');
  }

  void care(int kind) {
    if (kind < 0 || kind > 2) throw const GameRule('Неизвестный уход.');
    // A paid care event and its visual replay are the same daily purchase.
    if (kind != 1 && cared.contains(kind)) return;
    if (needs[kind] == 100) {
      throw const GameRule('Уже всё отлично! Монеты сохраним.');
    }
    final price = careCost(kind);
    if (wallet[0] < price) {
      throw const GameRule(
        'Не хватает монет в «Сейчас». Выполни задание или переведи из другого конверта.',
      );
    }
    wallet[0] -= price;
    needs[kind] = min(100, needs[kind] + [25, 20, 25][kind]);
    cared.add(kind);
    if (kind == 0) purchased.add('food_refill');
    if (kind == 2) purchased.add('clean_care');
    if (price > 0) {
      _recordFinance(
        FinanceMutation(
          kind: 'care',
          category: 'mandatory',
          amount: price,
          fromWallet: 0,
        ),
      );
    }
  }

  /// Food and species-specific cleaning are consumables from the canon store.
  /// Play itself is free; buying the ball is a separate permanent want.
  int careCost(int kind) {
    if (kind < 0 || kind > 2) throw const GameRule('Неизвестный уход.');
    if (cared.contains(kind)) return 0;
    return const [10, 0, 5][kind];
  }

  void giveWater() {
    completed.add('care:water:$day');
  }

  /// Первый план периода неизменяем; следующие версии требуют явной причины.
  void confirmPlan(List<int> split, {String? reason}) {
    if (split.length != 3 || split.any((v) => v < 0)) {
      throw const GameRule(
        'План должен состоять из трёх неотрицательных сумм.',
      );
    }
    if (split.every((v) => v == 0) && wallet[0] != 0) {
      throw const GameRule(
        'Распредели хотя бы одну монетку — план не бывает пустым.',
      );
    }
    if (split.reduce((a, b) => a + b) > wallet[0]) {
      throw GameRule(
        'В «Сейчас» сейчас ${wallet[0]} монет. План не может быть больше доступного.',
      );
    }
    final normalizedReason = reason?.trim();
    if (planConfirmed &&
        (normalizedReason == null || normalizedReason.isEmpty)) {
      throw const GameRule('Укажи причину пересмотра плана.');
    }
    plan = List<int>.from(split);
    if (!planConfirmed) {
      plansConfirmed++;
      planVersions = [PlanVersion(List<int>.from(split), 'baseline')];
    } else {
      planVersions = [
        ...planVersions,
        PlanVersion(List<int>.from(split), normalizedReason!),
      ];
    }
    planConfirmed = true;
  }

  /// Canon care shares the room's daily payment; permanent wants cost once.
  void buyItem(CatalogItem item) {
    if (item.id == 'food_refill' || item.id == 'food') {
      care(0);
      return;
    }
    if (item.id == 'clean_care' || item.id == 'shampoo') {
      care(2);
      return;
    }
    if (!item.required && purchased.contains(item.id)) {
      throw const GameRule('Эта вещь уже в комнате. Выбери что-то другое!');
    }
    if (wallet[0] < item.price) {
      throw GameRule(
        'Не хватает ${item.price - wallet[0]} монет в «Сейчас». Выполни задание или переведи из другого конверта.',
      );
    }
    wallet[0] -= item.price;
    purchased.add(item.id);
    if (item.id == 'cap' || item.id == 'bow') equippedWearable = item.id;
    if (item.need >= 0 && item.needBoost > 0) {
      needs[item.need] = min(100, needs[item.need] + item.needBoost);
    }
    _recordFinance(
      FinanceMutation(
        kind: 'purchase',
        category: item.required ? 'mandatory' : 'wants',
        amount: item.price,
        fromWallet: 0,
      ),
    );
  }

  void toggleWearable(String id) {
    if (!{'cap', 'bow'}.contains(id) || !purchased.contains(id)) {
      throw const GameRule('Сначала купи этот аксессуар.');
    }
    equippedWearable = equippedWearable == id ? null : id;
  }

  int get visibleAccessory => switch (equippedWearable) {
    'cap' => 3,
    'bow' => 4,
    _ => accessory,
  };

  DayFact get currentPeriodSummary => DayFact(
    day,
    List<int>.unmodifiable(plan),
    List<int>.unmodifiable(wallet),
    cared.length == 3,
    planVersions: List<PlanVersion>.unmodifiable([
      for (final version in planVersions)
        PlanVersion(List<int>.unmodifiable(version.split), version.reason),
    ]),
    mandatorySpent: periodActivity.known ? periodActivity.mandatorySpent : null,
    wantsSpent: periodActivity.known ? periodActivity.wantsSpent : null,
    savingsDeposits: periodActivity.known
        ? periodActivity.savingsDeposits
        : null,
    savingsWithdrawals: periodActivity.known
        ? periodActivity.savingsWithdrawals
        : null,
    goalSpent: periodActivity.known ? periodActivity.goalSpent : null,
    income: periodActivity.known ? periodActivity.income : null,
  );

  void endDay({bool reviewed = false, String? explanation}) {
    if (reviewed && !planConfirmed) {
      throw const GameRule('Сначала составим план и посмотрим его итоги.');
    }
    final summary = currentPeriodSummary;
    final normalizedExplanation = explanation?.trim();
    if (reviewed &&
        summary.hasPlanDeviation &&
        (normalizedExplanation == null || normalizedExplanation.isEmpty)) {
      throw const GameRule('Объясни, почему факт отличается от плана.');
    }
    if (planConfirmed) {
      final fact = DayFact(
        summary.day,
        summary.plan,
        summary.wallet,
        summary.caredAll,
        planVersions: summary.planVersions,
        mandatorySpent: summary.mandatorySpent,
        wantsSpent: summary.wantsSpent,
        savingsDeposits: summary.savingsDeposits,
        savingsWithdrawals: summary.savingsWithdrawals,
        goalSpent: summary.goalSpent,
        income: summary.income,
        planFactReviewed: reviewed,
        planFactExplanation:
            reviewed && normalizedExplanation?.isNotEmpty == true
            ? normalizedExplanation
            : null,
      );
      facts = [...facts, fact];
      if (fact.qualifiesForGrowth) qualifyingPeriods++;
      _promoteStage();
      if (facts.length > 5) facts = facts.sublist(facts.length - 5);
    }
    if (cared.length == 3) careDays++;
    cared.clear();
    plan = [0, 0, 0];
    planConfirmed = false;
    planVersions = [];
    periodActivity = const PeriodActivity();
    day++;
    needs = [
      for (var index = 0; index < needs.length; index++)
        max(20, needs[index] - const [12, 8, 10][index]),
    ];
  }

  void buyGoal() {
    if (owned.contains(goalId)) {
      throw const GameRule('Эта мечта уже в комнате. Выбери следующую!');
    }
    if (wallet[1] < goal.price) {
      throw GameRule('Осталось накопить ${goal.price - wallet[1]} монет.');
    }
    wallet[1] -= goal.price;
    owned.add(goalId);
    _recordFinance(
      FinanceMutation(
        kind: 'goal_purchase',
        category: 'wants',
        amount: goal.price,
        fromWallet: 1,
      ),
    );
  }

  String period(Mission m, DateTime now) {
    final today = dateKey(now);
    final effective = maxDate.compareTo(today) > 0
        ? DateTime.parse(maxDate)
        : now;
    return switch (m.period) {
      'once' => 'once',
      'weekly' => dateKey(
        DateTime(
          effective.year,
          effective.month,
          effective.day,
        ).subtract(Duration(days: effective.weekday - 1)),
      ),
      _ => dateKey(effective),
    };
  }

  String rewardKey(Mission m, DateTime now) =>
      m.period == 'once' ? '${m.id}:once' : '${m.id}:period:$day';

  /// Completed once lessons stay practice across saves and reward-key formats.
  bool rewardClaimed(Mission m, DateTime now) =>
      (m.period == 'once' && completed.contains(m.id)) ||
      rewards.contains(rewardKey(m, now));

  /// Выполнено ли действие задания-действия в реальном состоянии.
  bool actionDone(Mission m) => switch (m.actionTag) {
    'plan' => plansConfirmed > 0,
    'saved' => storyMarks.contains('saved'),
    'purchase' => purchased.isNotEmpty,
    _ => false,
  };

  int finish(Mission m, int choice, DateTime now, {required bool withoutHint}) {
    if (!planConfirmed) {
      throw const GameRule('Сначала составим план для денег на этот день.');
    }
    if (m.kind == 'action') {
      if (!actionDone(m)) {
        throw const GameRule(
          'Сначала выполни действие в приложении — питомец уже ждёт!',
        );
      }
    } else if (choice != m.correct) {
      throw const GameRule('Посмотри объяснение и попробуй ещё раз.');
    }
    if (m.period == 'once' && rewardClaimed(m, now)) return 0;
    final today = dateKey(now);
    if (today.compareTo(maxDate) > 0) maxDate = today;
    final key = rewardKey(m, now);
    completed.add(m.id);
    if (withoutHint) independent.add(m.id);
    if (!rewards.add(key)) return 0;
    return _earnPeriodIncome();
  }

  /// One job or learning task earns income each game period. Replays remain
  /// available for practice; only Flutter/SQLite can commit a reward.
  int finishJob(
    String jobId, {
    required int period,
    bool completedQuickly = false,
    bool petHappy = false,
  }) {
    final job = householdJobs[jobId];
    if (job == null) {
      throw const GameRule('Неизвестное поручение.');
    }
    if (period != day || currentRoom != job.room) {
      throw const GameRule('Поручение относится к другому дню или комнате.');
    }
    if (!planConfirmed) {
      throw const GameRule('Сначала составим план для денег на этот день.');
    }
    final rewardKey = 'job:${job.id}:$day';
    final legacyDishKey = 'job:dishes:$day';
    final alreadyClaimed =
        rewards.contains(rewardKey) ||
        (job.id == 'J01' && rewards.contains(legacyDishKey));
    completed.add('job:${job.id}');
    if (job.id == 'J01') completed.add('job:dishes');
    rewards.add(rewardKey);
    if (job.id == 'J01') rewards.add(legacyDishKey);
    if (alreadyClaimed) return 0;
    final base = _earnPeriodIncome();
    if (base == 0) return 0;
    final bonus = (completedQuickly ? 5 : 0) + (petHappy ? 5 : 0);
    if (bonus > 0) {
      wallet[0] += bonus;
      _recordFinance(
        FinanceMutation(
          kind: 'reward',
          category: 'income',
          amount: bonus,
          toWallet: 0,
        ),
      );
    }
    return base + bonus;
  }

  int finishDishJob({
    required int period,
    bool completedQuickly = false,
    bool petHappy = false,
  }) => finishJob(
    'J01',
    period: period,
    completedQuickly: completedQuickly,
    petHappy: petHappy,
  );

  int _earnPeriodIncome() {
    if (!incomeAvailable) return 0;
    incomeClaimedDay = day;
    wallet[0] += 30;
    _recordFinance(
      const FinanceMutation(
        kind: 'reward',
        category: 'income',
        amount: 30,
        toWallet: 0,
      ),
    );
    return 30;
  }

  /// Сброс игрового прогресса: питомец и настройки сохраняются,
  /// деньги, задания, покупки и планы обнуляются.
  void resetProgress() {
    _pendingFinance.clear();
    _snapshotReplacement = true;
    wallet = [100, 0, 0];
    needs = [60, 65, 55];
    day = 1;
    incomeClaimedDay = 0;
    owned = {};
    completed = {};
    independent = {};
    rewards = {};
    cared = {};
    storyMarks = {};
    purchased = {};
    equippedWearable = null;
    careDays = 0;
    achievedStage = 1;
    qualifyingPeriods = 0;
    maxDate = '';
    lastLoginDate = '';
    needsUpdatedAtMs = 0;
    plan = [0, 0, 0];
    planConfirmed = false;
    plansConfirmed = 0;
    planVersions = [];
    periodActivity = const PeriodActivity();
    facts = [];
    demoMode = false;
  }

  /// Демонстрационный профиль: пять последовательных периодов с планом
  /// и фактом, готовые к показу без ожидания реального времени (§2.5.13).
  void applyDemoProfile() {
    _pendingFinance.clear();
    _snapshotReplacement = true;
    achievedStage = 1;
    qualifyingPeriods = 0;
    name ??= defaultNames[species];
    wallet = [55, 90, 45];
    needs = [80, 75, 85];
    day = 6;
    incomeClaimedDay = 6;
    goalId = 'house';
    owned = {'garden'};
    completed = {'M01', 'M02', 'M03', 'M05', 'M10', 'A01', 'A02'};
    independent = {'M01', 'M10'};
    rewards = {'M01:once', 'A01:once', 'A02:once'};
    purchased = {'food_refill', 'ball', 'stickers'};
    equippedWearable = null;
    careDays = 3;
    plansConfirmed = 5;
    storyMarks = {'saved', 'reserve'};
    plan = [20, 10, 10];
    planConfirmed = true;
    planVersions = [
      const PlanVersion([20, 10, 10], 'demo_baseline'),
    ];
    periodActivity = const PeriodActivity(known: false);
    facts = [
      const DayFact(1, [30, 10, 10], [40, 10, 10], true, synthetic: true),
      const DayFact(2, [25, 15, 10], [30, 25, 10], true, synthetic: true),
      const DayFact(3, [20, 20, 15], [25, 45, 15], false, synthetic: true),
      const DayFact(4, [20, 15, 15], [30, 60, 30], true, synthetic: true),
      const DayFact(5, [20, 10, 10], [55, 90, 45], true, synthetic: true),
    ];
    demoMode = true;
  }
}

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool _isCanonicalDateKey(String value) {
  if (value.isEmpty) return true;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && dateKey(parsed) == value;
}

class Mission {
  const Mission(
    this.id,
    this.title,
    this.skill,
    this.period,
    this.topic,
    this.kind,
    this.story,
    this.question,
    this.options,
    this.correct,
    this.explanation, {
    this.actionHint,
    this.actionTag,
  });
  final String id, title, skill, period, topic, story, question, explanation;

  /// 'choice' — ответ из вариантов; 'action' — реальное действие в приложении.
  final String kind;

  /// Учебная тема: budget | savings | shopping (см. topicNames в content.dart).
  final List<String> options;
  final int correct;

  /// Для заданий-действий: подсказка, где выполнить, и тег условия.
  final String? actionHint, actionTag;
}
