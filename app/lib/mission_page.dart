import 'package:flutter/material.dart';
import 'game.dart';
import 'ui.dart';
import 'story.dart';

class MissionPage extends StatefulWidget {
  const MissionPage({
    super.key,
    required this.mission,
    required this.practice,
    required this.onComplete,
    this.incomeAvailable = true,
  });
  final Mission mission;
  final bool practice;
  final bool incomeAvailable;
  final Future<int> Function(int, bool) onComplete;
  @override
  State<MissionPage> createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> {
  int? selected, reward;
  bool hint = false, wrong = false, busy = false;
  String? error;
  Mission get m => widget.mission;
  bool get isTraining => widget.practice || !widget.incomeAvailable;
  Future<void> check() async {
    if (busy) return;
    if (m.kind == 'action') {
      setState(() => busy = true);
      try {
        final value = await widget.onComplete(0, true);
        if (mounted) setState(() => reward = value);
      } on GameRule catch (e) {
        if (mounted) {
          setState(() => error = e.message);
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => error = 'Не удалось сохранить результат. Попробуй ещё раз.',
          );
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    if (selected == null) return;
    if (selected != m.correct) {
      setState(() {
        wrong = true;
        hint = true;
      });
      return;
    }
    if (widget.practice) {
      setState(() => reward = 0);
      return;
    }
    setState(() => busy = true);
    try {
      final value = await widget.onComplete(selected!, !hint);
      if (mounted) setState(() => reward = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось сохранить результат. Попробуй ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context) ? const CozyBackButton() : null,
      title: Text(isTraining ? 'Тренировка' : 'Маленькое открытие'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Tag(
                '${m.skill.toUpperCase()} · ${isTraining ? 'ТРЕНИРОВКА · БЕЗ МОНЕТ' : 'НАГРАДА: 30 МОНЕТ'}',
                icon: Icons.lightbulb_outline_rounded,
              ),
              const SizedBox(height: 20),
              Text(
                reward == null ? m.title : 'Вот это открытие!',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 18),
              if (reward == null) ...[
                if (m.kind == 'action') ...[
                  Surface(
                    color: peach,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.question,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          m.actionHint ?? '',
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFF9D3030)),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: busy ? null : check,
                    icon: const CozyIcon(Icons.verified_rounded),
                    label: Text(busy ? 'Сохраняем…' : 'Я всё сделал — проверь'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isTraining
                        ? 'Тренировка · без монет. Действие можно повторить, '
                              'но новый доход не появится.'
                        : 'Награда дастся, когда действие будет выполнено '
                              'по-настоящему: в плане, переводе или покупке.',
                    style: const TextStyle(color: muted),
                  ),
                ] else ...[
                  Text(
                    missionScenes[m.id] ?? '',
                    style: const TextStyle(color: muted, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Surface(
                    color: peach,
                    child: Text(
                      m.story,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    m.question,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < m.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        selected: selected == i,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            backgroundColor: selected == i ? sage : cream,
                            padding: const EdgeInsets.all(18),
                            side: BorderSide(
                              color: selected == i
                                  ? blue
                                  : const Color(0xFFE0C9A5),
                              width: selected == i ? 2 : 1,
                            ),
                          ),
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  selected = i;
                                  wrong = false;
                                  error = null;
                                }),
                          child: Row(
                            children: [
                              CozyIcon(
                                selected == i
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  m.options[i],
                                  style: const TextStyle(
                                    color: ink,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (wrong || hint)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Surface(
                        color: sage,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wrong ? 'Давай разберём вместе' : 'Подсказка',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(m.explanation),
                          ],
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFF9D3030)),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy || selected == null ? null : check,
                    child: Text(busy ? 'Сохраняем…' : 'Проверить решение'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => hint = true),
                    child: const Text('Разобраться с подсказкой'),
                  ),
                  const Text(
                    'Монеты из условия — учебный пример. Твой игровой бюджет от выбора ответа не уменьшается.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ] else ...[
                Surface(
                  color: sage,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CozyIcon(
                        Icons.verified_rounded,
                        color: blue,
                        size: 46,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        reward! > 0
                            ? 'От родителей за помощь: +$reward монет'
                            : 'Тренировка завершена',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (reward! > 0) ...[
                        const SizedBox(height: 6),
                        Text('+$reward монет в «Сейчас»'),
                      ],
                      const SizedBox(height: 10),
                      Text(m.explanation),
                      const SizedBox(height: 10),
                      Text(
                        reward! > 0
                            ? 'Награда сохранена. План можно уточнить с новым '
                                  'доходом, но сам план не переводит монеты '
                                  'между конвертами.'
                            : widget.practice
                            ? 'Основной кошелёк и прогресс не менялись.'
                            : 'Задание зачтено. Доход этого дня уже получен; новых монет не добавилось.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('К своим планам'),
                ),
                if (m.id == 'M06') ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ComparisonPage(),
                      ),
                    ),
                    child: const Text('Сравнить игрушку и домик'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({super.key});
  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  bool save = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context) ? const CozyBackButton() : null,
      title: const Text('Сравнить игрушку и домик'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Tag(
            'ТРЕНИРОВКА · КОШЕЛЁК НЕ МЕНЯЕТСЯ',
            icon: Icons.science_outlined,
          ),
          const SizedBox(height: 20),
          const Heading(
            'Одна сумма.\nДва разных плана.',
            subtitle:
                'После ухода свободно 35. На домик за 120 уже накоплено 50. Игрушка стоит 35.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('Отложить на домик'),
                selected: save,
                onSelected: (_) => setState(() => save = true),
                padding: const EdgeInsets.all(12),
              ),
              ChoiceChip(
                label: const Text('Купить игрушку'),
                selected: !save,
                onSelected: (_) => setState(() => save = false),
                padding: const EdgeInsets.all(12),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Surface(
            color: save ? sage : peach,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CozyIcon(
                  save
                      ? Icons.cottage_outlined
                      : Icons.sports_baseball_outlined,
                  size: 48,
                  color: blue,
                ),
                const SizedBox(height: 16),
                Text(
                  save ? 'На домик — 85 монет' : 'Игрушка уже у тебя',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  save
                      ? 'До домика осталось 35. Игрушку можно запланировать позже.'
                      : 'На домик остаётся 50. До него ещё 70 монет.',
                ),
                const SizedBox(height: 16),
                const Text('Свободный остаток: 0 монет'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (save ? 85 : 50) / 120,
                  minHeight: 10,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Какой результат сейчас важнее тебе? Оба выбора возможны. Полезно увидеть, от чего придётся отказаться.',
          ),
        ],
      ),
    ),
  );
}
