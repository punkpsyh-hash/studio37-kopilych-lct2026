import 'package:flutter/material.dart';
import 'game.dart';
import 'ui.dart';

class PeriodReviewDecision {
  const PeriodReviewDecision({this.explanation});
  final String? explanation;
}

/// A review of the exact period snapshot that the caller will close atomically.
class PeriodReviewSheet extends StatefulWidget {
  const PeriodReviewSheet({
    super.key,
    required this.summary,
    required this.qualifyingPeriods,
  });

  final DayFact summary;
  final int qualifyingPeriods;

  @override
  State<PeriodReviewSheet> createState() => _PeriodReviewSheetState();
}

class _PeriodReviewSheetState extends State<PeriodReviewSheet> {
  String? explanation;
  static const reasons = [
    'Понадобилось больше заботы',
    'Я решил отложить покупку',
    'Я выбрал другую покупку',
    'Я иначе распределил накопления',
  ];

  @override
  Widget build(BuildContext context) {
    final fact = widget.summary;
    final needsReason = fact.factKnown && fact.hasPlanDeviation;
    final values = [fact.mandatorySpent, fact.wantsSpent, fact.netSavings];
    const labels = ['Забота', 'Желания', 'Накопления'];
    final canGrow = fact.factKnown && fact.caredAll && fact.netSavings! > 0;
    return Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Heading(
            'Итоги дня ${fact.day}',
            subtitle: 'Сравним, что планировали и что получилось.',
          ),
          const SizedBox(height: 16),
          if (fact.planVersions.length > 1) ...[
            Text(
              'Первый план: забота ${fact.baselinePlan[0]}, '
              'желания ${fact.baselinePlan[1]}, накопления ${fact.baselinePlan[2]}.',
            ),
            const SizedBox(height: 8),
            const Text('Ниже — твой уточнённый план и результат.'),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[i],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'План: ${fact.revisedPlan[i]} · Факт: ${values[i] ?? 'неизвестен'}',
                    ),
                  ],
                ),
              ),
            ),
          if (!fact.factKnown)
            const Text(
              'В старом сохранении нет подробностей этого дня. '
              'Он останется в истории, а следующий можно пройти полностью.',
            )
          else if (needsReason) ...[
            const SizedBox(height: 8),
            const Text(
              'Результат отличается от плана. Что изменилось? '
              'Менять решение можно — монеты за это не отнимаются.',
            ),
            const SizedBox(height: 8),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: explanation == reason ? sage : null,
                    padding: const EdgeInsets.all(12),
                  ),
                  onPressed: () => setState(() => explanation = reason),
                  child: Semantics(
                    selected: explanation == reason,
                    child: Text(reason),
                  ),
                ),
              ),
          ] else
            const Text('План и факт совпали.'),
          const SizedBox(height: 12),
          Text(
            fact.caredAll
                ? 'Забота о друге выполнена.'
                : 'Сегодня забота выполнена не полностью.',
          ),
          if (fact.factKnown)
            Text(
              fact.netSavings! > 0
                  ? 'В накоплениях осталось на ${fact.netSavings} монет больше.'
                  : 'Сегодня накопления не увеличились.',
            ),
          const SizedBox(height: 8),
          Text(
            canGrow
                ? 'После сравнения этот день станет ${widget.qualifyingPeriods + 1}-м зачтённым днём. '
                      'Друг растёт после 3 и 5 таких дней.'
                : 'Для роста в одном дне нужны забота, вклад в накопления и сравнение плана с фактом. '
                      'Уже достигнутая стадия сохранится.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('finish-reviewed-period'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: needsReason && explanation == null
                ? null
                : () => Navigator.pop(
                    context,
                    PeriodReviewDecision(explanation: explanation),
                  ),
            child: const Text('Завершить день'),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Продолжить этот день'),
          ),
        ],
      ),
    );
  }
}
