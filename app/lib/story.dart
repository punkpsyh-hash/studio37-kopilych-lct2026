import 'game.dart';

class StoryTask {
  const StoryTask(
    this.label,
    this.target,
    this.done, {
    this.secondaryLabel,
    this.secondaryTarget,
  });

  final String label, target;
  final bool done;
  final String? secondaryLabel, secondaryTarget;
}

/// A short, action-driven guide for a newly adopted pet. The canonical
/// five-period curriculum below remains available for older saves and for
/// the rest of the first period. Each step is derived from saved game facts.
StoryTask? firstDayGuide(GameState state) {
  if (state.demoMode ||
      state.day != 1 ||
      state.name?.trim().isNotEmpty != true ||
      !state.completed.contains('intro-started')) {
    return null;
  }
  if (!state.cared.contains(1)) {
    return const StoryTask('О, мячик! Поиграем в гостиной.', 'play', false);
  }
  if (!state.planConfirmed || !state.completed.contains('canon:B02:1')) {
    return const StoryTask(
      'Я проголодался. Сначала запланируем монеты на заботу.',
      'B02',
      false,
    );
  }
  if (!state.cared.contains(0)) {
    return state.currentRoom == 'kitchen'
        ? const StoryTask('Корм на полке. Насыпь его в миску.', 'care', false)
        : const StoryTask('Пойдём на кухню за кормом.', 'room:kitchen', false);
  }
  if (!state.cared.contains(2)) {
    return state.currentRoom == 'bathroom'
        ? const StoryTask('Я испачкался. Поможешь помыться?', 'care', false)
        : const StoryTask(
            'После еды испачкался. Идём в ванную!',
            'room:bathroom',
            false,
          );
  }
  if (!state.purchased.contains('ball')) {
    return state.currentRoom == 'living'
        ? const StoryTask(
            'Сделаем заказ: корм, мыло и новая игрушка.',
            'catalog',
            false,
          )
        : const StoryTask('Теперь вернёмся в гостиную.', 'room:living', false);
  }
  if (!state.completed.contains('intro-toy-play')) {
    return const StoryTask('Поиграем с новым мячом!', 'play', false);
  }
  if (!state.completed.contains('intro-money')) {
    return const StoryTask(
      'Как тратить монеты каждый день?',
      'intro:money',
      false,
    );
  }
  if (!state.completed.contains('canon:S01:1')) {
    return const StoryTask(
      'Большая покупка дороже. Выберем мечту и будем копить!',
      'S01',
      false,
    );
  }
  if (!state.completed.contains('intro-goal')) {
    return StoryTask('Вот наша цель: ${state.goal.name}!', 'intro:goal', false);
  }
  return null;
}

/// Text for the two acknowledgement steps. Callers show one short message and
/// then persist it with GameController.acknowledgeIntro.
String? firstDayGuideExplanation(
  GameState state,
  String target,
) => switch (target) {
  'intro:money' =>
    'Шкалы сытости, радости и чистоты — вверху. Корм и чистота нужны каждый день, игра бесплатна. Первые 100 монет подарила семья. За дело родители дают до 30 монет за игровой период. Оставляй немного в запасе.',
  'intro:goal' =>
    'Большие покупки стоят дороже. Часть монет нужна для заботы, часть оставим в запасе, часть отложим на мечту. Когда накопим и купим «${state.goal.name}», она появится в доме.',
  _ => null,
};

class StoryChapter {
  const StoryChapter(
    this.title,
    this.scene,
    this.ending,
    this.prop,
    this.tasks,
  );

  final String title, scene, ending;
  final int prop;
  final List<StoryTask> tasks;

  bool get complete => tasks.every((task) => task.done);

  StoryTask? get next {
    for (final task in tasks) {
      if (!task.done) return task;
    }
    return null;
  }
}

final RegExp _canonMarker = RegExp(r'^canon:([^:]+):(\d+)$');

Map<String, Set<int>> _canonDays(GameState state) {
  final result = <String, Set<int>>{};
  for (final entry in state.completed) {
    final match = _canonMarker.firstMatch(entry);
    if (match == null) continue;
    final day = int.tryParse(match.group(2)!);
    if (day == null || day < 1) continue;
    result.putIfAbsent(match.group(1)!, () => <int>{}).add(day);
  }
  return result;
}

bool _canonOccurrenceDone(
  GameState state,
  Map<String, Set<int>> days,
  String id,
  int occurrence,
) => state.completed.contains(id) && (days[id]?.length ?? 0) >= occurrence;

int _realReviewCount(GameState state) => state.facts
    .where((fact) => !fact.synthetic && fact.factKnown && fact.planFactReviewed)
    .length;

bool _careOccurrenceDone(GameState state, int occurrence, Set<int> kinds) {
  final finished = state.facts
      .where((fact) => !fact.synthetic && fact.factKnown && fact.caredAll)
      .length;
  final current =
      kinds.every(
        (kind) => state.cared.contains(kind) || state.needs[kind] == 100,
      )
      ? 1
      : 0;
  return finished + current >= occurrence;
}

bool _incomeOccurrenceDone(GameState state, int occurrence) {
  final finished = state.facts
      .where(
        (fact) => !fact.synthetic && fact.factKnown && (fact.income ?? 0) > 0,
      )
      .length;
  final current = state.periodActivity.known && state.periodActivity.income > 0
      ? 1
      : 0;
  return finished + current >= occurrence;
}

bool _savingOccurrenceDone(GameState state, int occurrence) {
  final finished = state.facts
      .where(
        (fact) =>
            !fact.synthetic && fact.factKnown && (fact.netSavings ?? 0) > 0,
      )
      .length;
  final current =
      state.periodActivity.known && state.periodActivity.netSavings > 0 ? 1 : 0;
  return finished + current >= occurrence;
}

bool _ballDecisionDone(GameState state) =>
    state.purchased.contains('ball') ||
    state.completed.any((entry) => entry.startsWith('canon:ball-deferred:'));

bool _goalAchieved(GameState state) =>
    state.owned.contains(state.goalId) ||
    state.completed.any((entry) => entry.startsWith('canon:goal-achieved:'));

bool _goalDecisionDone(GameState state) =>
    _goalAchieved(state) ||
    state.completed.any((entry) => entry.startsWith('canon:goal-deferred:'));

List<StoryChapter> storyChapters(GameState state) {
  final name = state.name?.trim();
  final friend = name == null || name.isEmpty ? 'Твой друг' : name;
  final canonDays = _canonDays(state);

  StoryTask lesson(int occurrence, String id, String label) => StoryTask(
    label,
    id,
    _canonOccurrenceDone(state, canonDays, id, occurrence) &&
        (id != 'S02' || _savingOccurrenceDone(state, occurrence)),
  );

  StoryTask care(int occurrence, {bool includePlay = true}) => StoryTask(
    includePlay
        ? 'Позаботиться о друге: корм, игра и чистота'
        : 'Покормить друга и позаботиться о чистоте',
    'care',
    _careOccurrenceDone(state, occurrence, includePlay ? {0, 1, 2} : {0, 2}),
  );

  StoryTask review(int occurrence) => StoryTask(
    'Сравнить план с фактом и завершить период',
    'day',
    _realReviewCount(state) >= occurrence,
  );

  return [
    StoryChapter(
      'Кто в коробке?',
      'В новом доме ждёт коробка с мягким пледом. Выбери друга, его окрас и имя. Семейная записка объясняет: 100 игровых монет подарены на новоселье.',
      '$friend выбран тобой. Три комнаты открыты, а у первых монет есть понятный источник.',
      4,
      [
        StoryTask(
          'Выбрать друга и дать ему имя',
          'adoption',
          name != null && name.isNotEmpty,
        ),
      ],
    ),
    StoryChapter(
      'Первый общий день',
      '$friend осматривает новый дом. Сначала вы выбираете мечту и планируете деньги, затем помогаете семье и решаете, нужен ли новый мяч прямо сейчас.',
      'Необходимое, желания и накопления получили свои места. Доход не перепутан с переводом между конвертами.',
      0,
      [
        lesson(1, 'S01', 'Сравнить три мечты и выбрать свою'),
        lesson(1, 'B02', 'Составить исходный план по трём направлениям'),
        lesson(1, 'P01', 'Собрать учебную корзину необходимого'),
        lesson(1, 'B04', 'После дохода объяснённо уточнить план'),
        care(1),
        StoryTask(
          'Купить мяч или осознанно отложить покупку',
          'catalog',
          _ballDecisionDone(state),
          secondaryLabel: 'Отложить мяч',
          secondaryTarget: 'defer:ball',
        ),
        lesson(1, 'S02', 'Сделать первый вклад в мечту или запас'),
        review(1),
      ],
    ),
    StoryChapter(
      'Всё на месте',
      'Новый период начинается с собственного плана. После поручения в гостиной можно уточнить решение, позаботиться о друге и бесплатно поиграть.',
      'Купленная вещь остаётся в доме, а сама игра не требует новой оплаты.',
      2,
      [
        lesson(2, 'B02', 'Составить исходный план периода'),
        StoryTask(
          'Разложить игрушки и книги по местам',
          'job:J02',
          _incomeOccurrenceDone(state, 2),
        ),
        lesson(2, 'B04', 'После дохода объяснённо уточнить план'),
        care(2, includePlay: false),
        StoryTask(
          'Поиграть с другом бесплатно',
          'play',
          _careOccurrenceDone(state, 2, {1}),
        ),
        lesson(2, 'S02', 'Сделать следующий вклад'),
        review(2),
      ],
    ),
    StoryChapter(
      'Забота без спешки',
      'Вы начинаете с плана 15 / 10 / 15. После полотенец решаете отложить наклейки и направить эти 10 монет в накопления.',
      'План можно менять с понятной причиной. В истории остаются и исходная, и новая версии.',
      7,
      [
        lesson(3, 'B02', 'Составить план 15 / 10 / 15'),
        StoryTask(
          'Сложить два полотенца и убрать их на полку',
          'job:J03',
          _incomeOccurrenceDone(state, 3),
        ),
        lesson(3, 'B04', 'Объяснить перенос 10 монет в накопления'),
        care(3),
        lesson(3, 'S02', 'Сделать вклад по уточнённому плану'),
        review(3),
      ],
    ),
    StoryChapter(
      'Какая мечта наша?',
      'После сортировки упаковок вы снова сравниваете три цели. Цель можно оставить или сменить: уже отложенные монеты не исчезнут.',
      'Цена помогает понять путь к цели, но не делает дорогую мечту единственно правильной.',
      5,
      [
        lesson(4, 'B02', 'Составить исходный план периода'),
        StoryTask(
          'Разложить упаковки по форме и значку',
          'job:J04',
          _incomeOccurrenceDone(state, 4),
        ),
        lesson(4, 'B04', 'После дохода объяснённо уточнить план'),
        lesson(2, 'S01', 'Снова сравнить цели и выбрать свою'),
        care(4),
        lesson(4, 'S02', 'Продолжить копить без обнуления'),
        review(4),
      ],
    ),
    StoryChapter(
      'Новоселье',
      'До новоселья остаётся один период. Вы готовите полки, проверяете дорогую покупку и смотрите на реальный путь к выбранной мечте.',
      _goalAchieved(state)
          ? 'Одна из ваших мечт появилась в доме. $friend празднует ваш общий путь.'
          : 'До мечты ещё есть путь, и это честный результат. $friend ценит вашу заботу так же сильно.',
      6,
      [
        lesson(5, 'B02', 'Составить исходный план периода'),
        StoryTask(
          'Протереть полки и убрать салфетку',
          'job:J05',
          _incomeOccurrenceDone(state, 5),
        ),
        lesson(5, 'B04', 'После дохода объяснённо уточнить план'),
        care(5),
        lesson(5, 'S02', 'Сделать последний вклад истории'),
        lesson(1, 'P06', 'Проверить покупку, на которую пока не хватает'),
        StoryTask(
          state.wallet[1] >= state.goal.price
              ? 'Решить, покупать ли «${state.goal.name}» за ${state.goal.price} монет'
              : 'До «${state.goal.name}» не хватает ${state.goal.price - state.wallet[1]} монет',
          'dreams',
          _canonOccurrenceDone(state, canonDays, 'P06', 1) &&
              _goalDecisionDone(state),
          secondaryLabel: state.wallet[1] >= state.goal.price
              ? 'Продолжить копить · уже ${state.wallet[1]} монет'
              : 'Продолжить копить · ${state.wallet[1]} из ${state.goal.price}',
          secondaryTarget: 'defer:dream',
        ),
        review(5),
      ],
    ),
  ];
}

int currentChapter(GameState state) {
  final chapters = storyChapters(state);
  final index = chapters.indexWhere((chapter) => !chapter.complete);
  return index < 0 ? chapters.length : index;
}

/// The only short story instruction that should be shown or routed now.
StoryTask? storyActiveTask(GameState state) {
  for (final chapter in storyChapters(state)) {
    final task = chapter.next;
    if (task != null) return task;
  }
  return null;
}

// Legacy missions remain optional practice. Their authored context is kept here
// for MissionPage and is deliberately separate from the canonical route above.
const missionScenes = {
  'M01':
      'В новом доме нашлись три конверта. Помоги питомцу подписать их и распределить первые монеты.',
  'M02':
      'Питомец проснулся, а на ярмарке появилось красивое украшение. Сначала решите, на что хватит бюджета.',
  'M03':
      'На полке пока пусто. Питомец нарисовал уютный домик и хочет понять, сколько осталось до покупки.',
  'M04':
      'У двери понадобился коврик для мокрых лап. Хорошо, что вы подумали о запасе заранее.',
  'M05':
      'На ярмарке два продавца предлагают одну и ту же вещь. Вместе проверьте условия покупки.',
  'M06':
      'В витрине новая игрушка, а в конверте мечты уже есть накопления. Питомец предлагает посчитать оба пути.',
  'M07':
      'Яркая вывеска обещает выгоду. Питомец предлагает сначала проверить числа.',
  'M08':
      'Для мастерской нужны две вещи. Питомец заметил набор — посчитайте, выгоден ли он.',
  'M09':
      'Старый мяч ещё скачет по коврику. До мечты совсем немного: что выбрать сейчас?',
  'M10':
      'Впереди три дня подготовки к празднику. Запланируйте заботу на весь период.',
  'M11':
      'Питомец увидел сад и задумался о новой мечте. Накопления уже есть — их не нужно начинать сначала.',
  'M12':
      'Последняя страница альбома — план на новые дни. Учтите заботу, мечту и запас.',
};
