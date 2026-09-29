import 'package:flutter/material.dart';
import 'content.dart';
import 'controller.dart';
import 'game.dart';
import 'ui.dart';

/// Раздел взрослого (§2.5.12, §3.5 ТЗ): цели, темы, общий прогресс,
/// демонстрационный профиль, подтверждаемые сброс и удаление данных.
/// Барьер — простой вопрос от случайных детских тапов, не защита паролем.
class AdultGate extends StatefulWidget {
  const AdultGate({super.key, required this.controller});
  final GameController controller;
  @override
  State<AdultGate> createState() => _AdultGateState();
}

class _AdultGateState extends State<AdultGate> {
  final answer = TextEditingController();
  bool unlocked = false, wrong = false;
  final int a = 3 + DateTime.now().day % 4, b = 4 + DateTime.now().month % 3;

  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!unlocked) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: Navigator.canPop(context) ? const CozyBackButton() : null,
          title: const Text('Раздел взрослого'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Heading(
                    'Этот раздел — для взрослых',
                    subtitle:
                        'Здесь можно посмотреть прогресс, включить деморежим и управлять данными. Монеты остаются игровыми.',
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: answer,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Сколько будет $a + $b?',
                      errorText: wrong ? 'Попробуй ещё раз' : null,
                    ),
                    onSubmitted: (_) => check(),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: check, child: const Text('Войти')),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AdultPage(controller: widget.controller);
  }

  void check() {
    if (int.tryParse(answer.text.trim()) == a + b) {
      setState(() => unlocked = true);
    } else {
      setState(() => wrong = true);
    }
  }
}

class AdultPage extends StatefulWidget {
  const AdultPage({super.key, required this.controller});
  final GameController controller;
  @override
  State<AdultPage> createState() => _AdultPageState();
}

class _AdultPageState extends State<AdultPage> {
  GameController get c => widget.controller;
  GameState get s => c.state!;

  Future<bool> confirm(
    String title,
    String body,
    Future<void> Function() run,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await run();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Готово.')));
        }
        return true;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is GameRule
                    ? error.message
                    : 'Не удалось сохранить изменение. Попробуйте ещё раз.',
              ),
            ),
          );
        }
      }
    }
    return false;
  }

  Future<void> _enterQuickCheck() async {
    final changed = await confirm(
      'Начать быструю проверку?',
      'Откроется отдельный демопрофиль. Основной питомец, монеты и прогресс сохранятся. Если демо уже запускали, оно продолжится с сохранённого места.',
      c.startDemo,
    );
    if (changed && mounted) Navigator.of(context).pop();
  }

  Future<void> _resetQuickCheck() async {
    final changed = await confirm(
      'Сбросить только демопрофиль?',
      'Демопрофиль начнётся с первого периода и стартовых 100 монет. Его планы, решения и журнал удалятся. Основной профиль сохранится.',
      c.resetDemo,
    );
    if (changed && mounted) Navigator.of(context).pop();
  }

  Future<void> _exitQuickCheck() async {
    final changed = await confirm(
      'Вернуться в основной профиль?',
      'Демопрогресс сохранится отдельно. Откроются основной питомец и его монеты.',
      c.exitDemo,
    );
    if (changed && mounted) Navigator.of(context).pop();
  }

  Widget _quickCheckSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Tag('БЫСТРАЯ ПРОВЕРКА', icon: Icons.fact_check_outlined),
      const SizedBox(height: 10),
      Surface(
        color: sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.demoMode ? 'Демопрофиль включён' : 'Маршрут для организаторов',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              s.demoMode
                  ? 'Пройдите пять периодов подряд без ожидания. Финансовые решения и последствия настоящие; основной профиль хранится отдельно.'
                  : 'Отдельный демопрофиль позволяет проверить не менее пяти периодов без ожидания. Основной профиль не меняется.',
            ),
            const SizedBox(height: 10),
            const Text(
              '1. При первом запуске выберите питомца; демо сохраняет его вид. Проверьте стартовые монеты и цель.',
            ),
            const Text(
              '2. Составьте план до расходов, выполните задание и получите игровые монеты.',
            ),
            const Text(
              '3. Купите обязательное и желаемое, проверьте сообщение при нехватке монет.',
            ),
            const Text(
              '4. Отложите монеты на цель, завершите период и сравните план с фактом.',
            ),
            const Text(
              '5. Повторите цикл до пяти периодов, проверьте прогресс, перезапуск и сохранение.',
            ),
            const SizedBox(height: 12),
            if (!s.demoMode)
              FilledButton.icon(
                key: const ValueKey('adult-quick-check-start'),
                onPressed: c.busy ? null : _enterQuickCheck,
                icon: const CozyIcon(Icons.smart_display_outlined),
                label: const Text('Начать быструю проверку'),
              )
            else ...[
              FilledButton.icon(
                key: const ValueKey('adult-quick-check-play'),
                onPressed: c.busy ? null : () => Navigator.of(context).pop(),
                icon: const CozyIcon(Icons.smart_display_outlined),
                label: const Text('Вернуться в игру'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('adult-quick-check-reset'),
                onPressed: c.busy ? null : _resetQuickCheck,
                icon: const CozyIcon(Icons.restart_alt_rounded),
                label: const Text('Сбросить демо и начать заново'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('adult-quick-check-exit'),
                onPressed: c.busy ? null : _exitQuickCheck,
                child: const Text('Вернуться в основной профиль'),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context) ? const CozyBackButton() : null,
        title: const Text('Раздел взрослого'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Heading(
                  'Прогресс обучения',
                  subtitle:
                      'Краткая сводка по темам финансовой грамотности. Данные хранятся только на этом устройстве.',
                ),
                const SizedBox(height: 20),
                Surface(
                  color: peach,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.name ?? 'Питомец ещё не выбран'} · день ${s.day}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Стадия роста: ${s.stageName} (${s.stage} из 3)'),
                      Text(
                        'Подтверждённых планов: ${s.plansConfirmed} · полных дней заботы: ${s.careDays}',
                      ),
                      Text('Игровых монет всего: ${s.total}'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _quickCheckSection(context),
                const SizedBox(height: 14),
                const Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Зачем эта игра',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Ребёнок учится различать обязательную заботу и желания, '
                        'составлять план, откладывать на цель и сравнивать решения с результатом. '
                        'Монеты игровые. Ошибку можно обсудить и попробовать иначе; '
                        'оценки финансового поведения ребёнка здесь нет.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Tag('ТЕМЫ', icon: Icons.menu_book_rounded),
                const SizedBox(height: 10),
                for (var t = 0; t < topicNames.length; t++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _topicCard(t),
                  ),
                const SizedBox(height: 14),
                const Tag('ДАННЫЕ', icon: Icons.privacy_tip_outlined),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Имя питомца, прогресс и журнал игровых монет хранятся на этом устройстве. '
                        'Основной и тестовый профили можно сбросить отдельно. '
                        'Кнопка удаления ниже удаляет оба профиля и их журналы.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: c.busy
                            ? null
                            : () => confirm(
                                'Сбросить прогресс?',
                                s.demoMode
                                    ? 'Сбросится только тестовый прогресс. Основной профиль сохранится.'
                                    : 'Питомец и настройки сохранятся. Задания, покупки и планы сбросятся; монеты вернутся к стартовым 100.',
                                () => c.change(
                                  'Сброс прогресса',
                                  (state) => state.resetProgress(),
                                ),
                              ),
                        icon: const CozyIcon(Icons.restart_alt_rounded),
                        label: const Text('Сбросить прогресс'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: c.busy
                            ? null
                            : () => confirm(
                                'Удалить все данные?',
                                'Удаляется всё: питомец, прогресс и журнал. Приложение вернётся к первому запуску. Действие необратимо.',
                                () async {
                                  await c.store.wipe();
                                  await c.load();
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                    ).popUntil((route) => route.isFirst);
                                  }
                                },
                              ),
                        icon: const CozyIcon(Icons.delete_forever_rounded),
                        label: const Text('Удалить все данные'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Микрофон используется только для голосового ответа питомцу и работает без сети; отказ от разрешения не ломает игру. Звук и анимации можно отключить в настройках.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _topicCard(int t) {
    final topics = ['budget', 'savings', 'shopping'];
    final inTopic = allMissions.where((m) => m.topic == topics[t]);
    final done = inTopic.where((m) => s.completed.contains(m.id)).length;
    final icons = [
      Icons.account_balance_wallet_outlined,
      Icons.savings_outlined,
      Icons.shopping_basket_outlined,
    ];
    return Surface(
      color: Colors.white,
      child: Row(
        children: [
          CozyIcon(icons[t], size: 32, color: blue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topicNames[t],
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: done / inTopic.length,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFF749273),
                  backgroundColor: const Color(0xFFE9E4DA),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$done/${inTopic.length}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
        ],
      ),
    );
  }
}
