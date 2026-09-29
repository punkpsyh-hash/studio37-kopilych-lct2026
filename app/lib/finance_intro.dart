import 'package:flutter/material.dart';

import 'ui.dart';

const financeIntroTitle = 'Как играть';
const financeIntroPurpose =
    'Заботься о питомце и учись выбирать, куда направить игровые монеты.';
const financeIntroDecisions = [
  'Забота обязательна: сначала корм и чистота.',
  'Желания можно отложить, если сейчас важнее другое.',
  'Накопления приближают выбранную цель.',
];

class FinanceIntroContent extends StatelessWidget {
  const FinanceIntroContent({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        '$financeIntroTitle. $financeIntroPurpose ${financeIntroDecisions.join(' ')}',
    excludeSemantics: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            financeIntroTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
        ],
        const Text(financeIntroPurpose),
        const SizedBox(height: 10),
        for (var i = 0; i < financeIntroDecisions.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CozyIcon(
                const [
                  Icons.task_alt_rounded,
                  Icons.favorite_border_rounded,
                  Icons.savings_outlined,
                ][i],
                color: blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(financeIntroDecisions[i])),
            ],
          ),
          if (i < financeIntroDecisions.length - 1) const SizedBox(height: 6),
        ],
      ],
    ),
  );
}

Future<void> showFinanceIntro(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: const FinanceIntroContent(),
          ),
        ),
      ),
    );

const financeGlossary = <(String, String)>[
  ('Доход', 'Игровые монеты, которые приходят за задания и помощь.'),
  ('Обязательные расходы', 'Покупки для регулярной заботы о питомце, например корм.'),
  ('Необязательные расходы', 'Покупки для радости, которые можно отложить.'),
  ('Бюджет', 'План: сколько монет потратить и сколько отложить.'),
  ('Накопления', 'Монеты, отложенные отдельно от денег для покупок.'),
  ('Цель', 'Предмет с известной ценой, на который ты копишь.'),
  ('План и факт', 'План — решение до покупок. Факт — что получилось после них.'),
];

class FinanceGlossaryContent extends StatelessWidget {
  const FinanceGlossaryContent({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    children: [
      Text('Словарик', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final (term, meaning) in financeGlossary)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(term, style: Theme.of(context).textTheme.titleMedium),
              Text(meaning),
            ],
          ),
        ),
    ],
  );
}

Future<void> showFinanceGlossary(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: const FinanceGlossaryContent(),
        ),
      ),
    );
