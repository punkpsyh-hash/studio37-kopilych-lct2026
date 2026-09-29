import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'catalog_page.dart';
import 'content.dart';
import 'controller.dart';
import 'game.dart';
import 'ui.dart';

typedef ActionRunner =
    Future<bool> Function(
      String label,
      void Function(GameState) action, {
      String? success,
      String? id,
    });

class BudgetPage extends StatefulWidget {
  const BudgetPage({
    super.key,
    required this.controller,
    required this.onAction,
    required this.onDreams,
    this.useMeshyModels = true,
    this.onSceneCare,
  });
  final GameController controller;
  final ActionRunner onAction;
  final VoidCallback onDreams;
  final bool useMeshyModels;
  final ValueChanged<String>? onSceneCare;
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  int from = 0, to = 1;
  final amount = TextEditingController(text: '20');
  final planCtl = [
    TextEditingController(text: '15'),
    TextEditingController(text: '5'),
    TextEditingController(text: '10'),
  ];
  String? error;
  GameState get s => widget.controller.state!;
  @override
  void dispose() {
    amount.dispose();
    for (final c in planCtl) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> history() async {
    List<Map<String, Object?>> entries;
    try {
      entries = await widget.controller.store.history();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось прочитать историю. Попробуй ещё раз.',
        );
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cream,
      builder: (context) => Sheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Heading(
              'История монет',
              subtitle: 'Последние 60 действий. Стартовый бюджет — 100 монет.',
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Text('Пока только начало вашей истории.'),
            for (final row in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(row['label'] as String)),
                    const SizedBox(width: 12),
                    Text(
                      (row['delta'] as int) > 0
                          ? '+${row['delta']}'
                          : '${row['delta']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Итоги периода: подтверждённый план против факта на конец дня (§2.5.11).
  Future<void> periodSummary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cream,
      builder: (context) => Sheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Heading(
              'Итоги периодов',
              subtitle:
                  'План — что решил утром. Факт — что получилось к вечеру. Сравнивать их — полезная привычка.',
            ),
            const SizedBox(height: 18),
            if (s.planConfirmed)
              Surface(
                color: sage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Исходный план дня ${s.day}: ${_planText(s.planVersions.first.split)}',
                    ),
                    if (s.planVersions.length > 1)
                      Text(
                        'Последняя версия: ${_planText(s.planVersions.last.split)} · ${_reasonText(s.planVersions.last.reason)}',
                      ),
                  ],
                ),
              )
            else
              const Surface(child: Text('План на сегодня ещё не подтверждён.')),
            const SizedBox(height: 12),
            if (s.facts.isEmpty)
              const Text(
                'Завершённых периодов пока нет. Подтверди план и заверши день — здесь появятся итоги.',
              ),
            for (final f in s.facts.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Surface(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'День ${f.day}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('Исходный план: ${_planText(f.baselinePlan)}'),
                      if (f.planVersions.length > 1)
                        for (final version in f.planVersions.skip(1))
                          Text(
                            'Пересмотр: ${_planText(version.split)} · ${_reasonText(version.reason)}',
                          ),
                      if (f.factKnown) ...[
                        Text(
                          'Факт: обязательное ${f.mandatorySpent} · желания ${f.wantsSpent} · чистые накопления ${f.netSavings}',
                        ),
                        Text(
                          'Накопления: внесено ${f.savingsDeposits} · снято ${f.savingsWithdrawals} · доход ${f.income}',
                        ),
                        if (f.goalSpent! > 0)
                          Text('На мечту из накоплений: ${f.goalSpent}'),
                      ] else
                        const Text(
                          'Факт по категориям неизвестен: старое сохранение не содержало детализацию.',
                        ),
                      Text(
                        'Конверты в конце: Сейчас ${f.wallet[0]} · Мечта ${f.wallet[1]} · Запас ${f.wallet[2]}',
                      ),
                      if (f.synthetic)
                        const Text('Учебный демо-пример, не реальная история.'),
                      Text(
                        f.planFactReviewed
                            ? 'План и факт просмотрены.'
                            : 'Сравнение плана с фактом не подтверждено.',
                      ),
                      if (f.planFactExplanation != null)
                        Text('Что изменилось: ${f.planFactExplanation}'),
                      Text(
                        f.qualifiesForGrowth
                            ? 'Этот день зачтён для роста.'
                            : 'Этот день сохранён в истории без зачёта для роста.',
                      ),
                      Text(
                        f.caredAll
                            ? 'Весь уход выполнен.'
                            : 'Уход выполнен частично — это нормально, завтра получится лучше.',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _planText(List<int> split) =>
      'обязательное ${split[0]} · желания ${split[1]} · накопления ${split[2]}';

  String _reasonText(String reason) => switch (reason) {
    'income_received' => 'получен новый доход',
    'priorities_changed' => 'изменились приоритеты',
    'price_changed' => 'изменилась цена',
    'legacy_baseline' => 'перенесено из старого сохранения',
    'demo_baseline' => 'учебный пример',
    _ => reason,
  };

  Future<String?> _revisionReason() => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Почему меняем план?'),
      content: const Text(
        'Исходный план останется в истории. Выбери причину новой версии.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'priorities_changed'),
          child: const Text('Новые приоритеты'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'income_received'),
          child: const Text('Получен доход'),
        ),
      ],
    ),
  );

  Future<void> confirmWithdrawal(int n, {int? source, int? target}) async {
    final origin = source ?? from;
    final destination = target ?? to;
    final remaining = s.wallet[origin] - n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Снимаем из накоплений?'),
        content: Text(
          origin == 1
              ? 'В «На мечту» лежит ${s.wallet[1]} монет на мечту «${s.goal.name}». После перевода останется $remaining. Мечта чуть отодвинется — это нормально, деньги всё ещё твои.'
              : 'В «Запас» лежит ${s.wallet[2]} монет на неожиданное. После перевода останется $remaining.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Перевести'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await widget.onAction(
      'Перевод $n: ${envelopeNames[origin]} → ${envelopeNames[destination]}',
      (state) => state.transfer(origin, destination, n),
      success:
          '$n монет теперь в «${envelopeNames[destination]}». Общая сумма не изменилась.',
    );
  }

  Future<void> _quickTransfer(int source, int target) async {
    if (source == target || s.wallet[source] <= 0 || widget.controller.busy) {
      return;
    }
    final count = s.wallet[source].clamp(0, 10);
    if (source == 1 || source == 2) {
      await confirmWithdrawal(count, source: source, target: target);
    } else {
      await widget.onAction(
        'Перевод $count: ${envelopeNames[source]} → ${envelopeNames[target]}',
        (state) => state.transfer(source, target, count),
        success: '$count монет теперь в «${envelopeNames[target]}».',
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Heading(
        'У каждой монеты\nесть свой план',
        subtitle: 'Сначала план — потом траты. Порадуйся завтра.',
      ),
      const SizedBox(height: 22),
      Surface(
        color: blue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ВСЕГО У ТЕБЯ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${s.total} монет',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Перевод между конвертами не тратит монеты.',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Surface(
            color: [peach, sage, const Color(0xFFF0E6CB)][i],
            child: Row(
              children: [
                CozyIcon(
                  [
                    Icons.shopping_bag_outlined,
                    Icons.flag_outlined,
                    Icons.shield_outlined,
                  ][i],
                  size: 30,
                  color: ink,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        envelopeNames[i],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          'Забота и маленькие радости',
                          'На то, что очень хочется',
                          'На неожиданное',
                        ][i],
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Coins(s.wallet[i]),
              ],
            ),
          ),
        ),
      const SizedBox(height: 18),
      Surface(
        color: sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CozyIcon(Icons.edit_calendar_rounded, color: blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'План на день ${s.day}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (s.planConfirmed)
                  const CozyIcon(Icons.check_circle_rounded, color: blue),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Реши до задания: сколько из «Сейчас» пойдёт на каждое направление. Исходный план сохранится, а изменение станет отдельной версией с причиной.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: TextField(
                        controller: planCtl[i],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: ['Забота', 'Желания', 'Накопления'][i],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.controller.busy
                  ? null
                  : () async {
                      final split = [
                        for (final c in planCtl) int.tryParse(c.text) ?? 0,
                      ];
                      final reason = s.planConfirmed
                          ? await _revisionReason()
                          : null;
                      if (s.planConfirmed && reason == null) return;
                      final ok = await widget.onAction(
                        s.planConfirmed
                            ? 'Пересмотр плана дня ${s.day}'
                            : 'Исходный план дня ${s.day}',
                        (state) => state.confirmPlan(split, reason: reason),
                        success: s.planConfirmed
                            ? 'Новая версия плана сохранена. Монеты остались в своих конвертах.'
                            : 'План сохранён. Монеты пока остались в «Сейчас». Вечером сравним план с фактом.',
                      );
                      if (ok) setState(() {});
                    },
              icon: const CozyIcon(Icons.check_rounded),
              label: Text(
                s.planConfirmed ? 'Создать новую версию' : 'Подтвердить план',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text('Переложим монеты?', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      DropdownButtonFormField<int>(
        icon: const RotatedBox(
          quarterTurns: 1,
          child: CozyIcon(Icons.chevron_right_rounded, size: 20),
        ),
        initialValue: from,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Откуда'),
        items: [
          for (var i = 0; i < 3; i++)
            DropdownMenuItem(
              value: i,
              child: Text('${envelopeNames[i]} · ${s.wallet[i]}'),
            ),
        ],
        onChanged: (v) => setState(() => from = v!),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        icon: const RotatedBox(
          quarterTurns: 1,
          child: CozyIcon(Icons.chevron_right_rounded, size: 20),
        ),
        initialValue: to,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Куда'),
        items: [
          for (var i = 0; i < 3; i++)
            DropdownMenuItem(value: i, child: Text(envelopeNames[i])),
        ],
        onChanged: (v) => setState(() => to = v!),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ],
        decoration: InputDecoration(
          labelText: 'Сколько монет',
          errorText: error,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('budget-minus-ten'),
              onPressed:
                  widget.controller.busy || from == to || s.wallet[to] == 0
                  ? null
                  : () => _quickTransfer(to, from),
              icon: const Icon(Icons.remove_rounded),
              label: Text('Вернуть ${s.wallet[to].clamp(0, 10)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('budget-plus-ten'),
              onPressed:
                  widget.controller.busy || from == to || s.wallet[from] == 0
                  ? null
                  : () => _quickTransfer(from, to),
              icon: const Icon(Icons.add_rounded),
              label: Text('Добавить ${s.wallet[from].clamp(0, 10)}'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: widget.controller.busy
            ? null
            : () async {
                final n = int.tryParse(amount.text);
                if (n == null || n <= 0 || from == to || n > s.wallet[from]) {
                  setState(
                    () => error = from == to
                        ? 'Нужны разные конверты'
                        : n == null || n <= 0
                        ? 'Введи целое число больше нуля'
                        : 'Доступно ${s.wallet[from]} монет',
                  );
                  return;
                }
                setState(() => error = null);
                if (from == 1 || from == 2) {
                  await confirmWithdrawal(n);
                } else {
                  await widget.onAction(
                    'Перевод $n: ${envelopeNames[from]} → ${envelopeNames[to]}',
                    (state) => state.transfer(from, to, n),
                    success:
                        '$n монет теперь в «${envelopeNames[to]}». Общая сумма не изменилась.',
                  );
                }
              },
        icon: const CozyIcon(Icons.swap_horiz_rounded),
        label: const Text('Перевести'),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () async {
          final action = await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              builder: (catalogContext) => CatalogPage(
                controller: widget.controller,
                onAction: widget.onAction,
                useMeshyModels: widget.useMeshyModels,
                onSceneCare: widget.onSceneCare,
                onOpenBudget: () => Navigator.pop(catalogContext),
              ),
            ),
          );
          if (mounted && action != null) widget.onSceneCare?.call(action);
        },
        icon: const CozyIcon(Icons.storefront_rounded),
        label: Text('Магазин: ${catalogItems.length} покупок'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.onDreams,
        icon: const CozyIcon(Icons.flag_outlined),
        label: const Text('Выбрать или исполнить мечту'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: periodSummary,
        icon: const CozyIcon(Icons.fact_check_outlined),
        label: const Text('Итоги периодов: план и факт'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: history,
        icon: const CozyIcon(Icons.history_rounded),
        label: const Text('История монет'),
      ),
    ],
  );
}
