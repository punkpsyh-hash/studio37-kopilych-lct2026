import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canon_lesson.dart';
import 'content.dart';
import 'game.dart';
import 'ui.dart';

class CanonLessonPage extends StatefulWidget {
  const CanonLessonPage({
    super.key,
    required this.lessonId,
    required this.state,
    required this.onSubmit,
    this.onGo,
  });

  final String lessonId;
  final GameState state;
  final Future<CanonLessonReceipt> Function(CanonLessonSubmission submission)
  onSubmit;
  final void Function(String route)? onGo;

  @override
  State<CanonLessonPage> createState() => _CanonLessonPageState();
}

class _CanonLessonPageState extends State<CanonLessonPage> {
  late final GameState _snapshot;
  late final bool _practice;
  late final TextEditingController _care;
  late final TextEditingController _wants;
  late final TextEditingController _savings;
  late final TextEditingController _transfer;

  String? _reason;
  String? _selectedGoal;
  String _transferTarget = 'dream';
  bool _food = false;
  bool _clean = false;
  bool _ball = false;
  String? _rationale;
  bool _purchaseAttempted = false;
  String? _p06Resolution;
  bool _busy = false;
  int? _reward;
  CanonLessonReceipt? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!canonLessonIds.contains(widget.lessonId)) {
      throw ArgumentError.value(
        widget.lessonId,
        'lessonId',
        'Unknown canonical lesson',
      );
    }
    _snapshot = GameState.fromJson(widget.state.toJson());
    _practice = _snapshot.completed.contains(
      canonLessonMarker(widget.lessonId, _snapshot.day),
    );
    final initialPlan =
        widget.lessonId == 'B02' && _snapshot.planVersions.isNotEmpty
        ? _snapshot.planVersions.first.split
        : _snapshot.planConfirmed
        ? _snapshot.plan
        : [0, 0, 0];
    _care = TextEditingController(text: '${initialPlan[0]}');
    _wants = TextEditingController(text: '${initialPlan[1]}');
    _savings = TextEditingController(text: '${initialPlan[2]}');
    _transfer = TextEditingController(
      text: '${_snapshot.wallet[0] <= 0 ? 1 : _snapshot.wallet[0].clamp(1, 5)}',
    );
    _selectedGoal = _snapshot.goalId;
  }

  @override
  void dispose() {
    _care.dispose();
    _wants.dispose();
    _savings.dispose();
    _transfer.dispose();
    super.dispose();
  }

  List<int>? get _split {
    final values = [
      int.tryParse(_care.text),
      int.tryParse(_wants.text),
      int.tryParse(_savings.text),
    ];
    return values.any((value) => value == null) ? null : values.cast<int>();
  }

  String get _title => switch (widget.lessonId) {
    'B02' => 'Три направления плана',
    'B04' => 'План можно изменить',
    'S01' => 'Выбираем мечту',
    'S02' => 'Мечта и запас',
    'P01' => 'Собираем необходимое',
    'P06' => 'Хочу, но пока не хватает',
    _ => '',
  };

  Future<void> _submit() async {
    setState(() => _error = null);
    final submission = _buildSubmission();
    if (submission == null) return;
    setState(() => _busy = true);
    try {
      final receipt = await widget.onSubmit(submission);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _reward = receipt.reward;
      });
    } on GameRule catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Не удалось сохранить действие. Попробуй ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  CanonLessonSubmission? _buildSubmission() {
    final id = widget.lessonId;
    if (id == 'B02' || id == 'B04') {
      final split = _split;
      if (split == null || split.any((value) => value < 0)) {
        _showError('Введи три целые суммы от нуля.');
        return null;
      }
      final total = split.fold<int>(0, (sum, value) => sum + value);
      if (total > _snapshot.wallet[0]) {
        _showError(
          'План больше доступной суммы на ${total - _snapshot.wallet[0]} монет.',
        );
        return null;
      }
      if (total == 0 && _snapshot.wallet[0] > 0) {
        _showError('Распредели хотя бы одну монету.');
        return null;
      }
      if (id == 'B04' && _reason == null) {
        _showError('Выбери причину изменения плана.');
        return null;
      }
      if (id == 'B04' && _samePlan(split, _snapshot.plan)) {
        _showError('Измени хотя бы одну сумму в плане.');
        return null;
      }
      if (id == 'B04' &&
          _reason == 'После дохода уточняю суммы' &&
          _snapshot.periodActivity.income <= 0) {
        _showError('Доход ещё не получен. Выбери другую причину.');
        return null;
      }
      return CanonLessonSubmission.capture(
        _snapshot,
        lessonId: id,
        practice: _practice,
        split: split,
        reason: _reason,
      );
    }
    if (id == 'S01') {
      return CanonLessonSubmission.capture(
        _snapshot,
        lessonId: id,
        practice: _practice,
        goalId: _selectedGoal,
      );
    }
    if (id == 'S02') {
      final amount = int.tryParse(_transfer.text);
      if (amount == null || amount <= 0) {
        _showError('Введи целую сумму больше нуля.');
        return null;
      }
      if (amount > _snapshot.wallet[0]) {
        _showError(
          'В «Сейчас» не хватает ${amount - _snapshot.wallet[0]} монет.',
        );
        return null;
      }
      return CanonLessonSubmission.capture(
        _snapshot,
        lessonId: id,
        practice: _practice,
        transferTarget: _transferTarget,
        amount: amount,
      );
    }
    if (id == 'P01') {
      final basket = <String>[
        if (_food) 'food_refill',
        if (_clean) 'clean_care',
        if (_ball) 'ball',
      ];
      if (!_food || !_clean || _ball) {
        _showError(
          'Пока не получилось: выбери корм за 10 и чистоту за 5. Мяч — желание, его можно решить отдельно.',
        );
        return null;
      }
      if (_rationale != 'Корм и чистота нужны питомцу сегодня') {
        _showError(
          'Подумай ещё раз: необходимое связано с заботой, которая нужна сегодня.',
        );
        return null;
      }
      return CanonLessonSubmission.capture(
        _snapshot,
        lessonId: id,
        practice: _practice,
        basketIds: basket,
        rationale: _rationale,
      );
    }
    if (!_purchaseAttempted) {
      _showError('Сначала попробуй купить лежанку и посмотри результат.');
      return null;
    }
    if (_p06Resolution == null) {
      _showError('Теперь выбери: отложить желание или изменить план.');
      return null;
    }
    return CanonLessonSubmission.capture(
      _snapshot,
      lessonId: id,
      practice: _practice,
      purchaseAttempted: true,
      p06Resolution: _p06Resolution,
      attemptedAvailable: _snapshot.wallet[0] >= 35 ? 30 : _snapshot.wallet[0],
      attemptedPrice: 35,
      useTeachingCopy: _snapshot.wallet[0] >= 35,
    );
  }

  void _showError(String message) => setState(() => _error = message);

  bool _samePlan(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context) ? const CozyBackButton() : null,
      title: Text(_title),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tag(
                    _practice
                        ? 'ТРЕНИРОВКА · КОШЕЛЁК НЕ МЕНЯЕТСЯ'
                        : widget.lessonId == 'P01' && !_snapshot.incomeAvailable
                        ? 'ДОХОД УЖЕ ПОЛУЧЕН · ЗАДАНИЕ БЕЗ МОНЕТ'
                        : 'ДЕНЬ ${_snapshot.day} · НАСТОЯЩЕЕ ДЕЙСТВИЕ',
                    icon: _practice
                        ? Icons.science_outlined
                        : Icons.task_alt_rounded,
                  ),
                  const SizedBox(height: 18),
                  if (_reward == null) _lessonBody() else _successBody(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _lessonBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      switch (widget.lessonId) {
        'B02' => _budgetBody(revision: false),
        'B04' => _budgetBody(revision: true),
        'S01' => _goalsBody(),
        'S02' => _transferBody(),
        'P01' => _basketBody(),
        'P06' => _insufficientBody(),
        _ => const SizedBox.shrink(),
      },
      if (_error != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Surface(
            color: peach,
            child: Text(
              _error!,
              key: const Key('canon-error'),
              style: const TextStyle(
                color: Color(0xFF8A2F25),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('canon-submit'),
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Сохраняем…' : _submitLabel),
      ),
    ],
  );

  String get _submitLabel => switch (widget.lessonId) {
    'B02' => 'Сохранить исходный план',
    'B04' => 'Сохранить новую версию',
    'S01' => 'Выбрать эту мечту',
    'S02' => 'Подтвердить перевод',
    'P01' => 'Проверить корзину',
    'P06' => 'Сохранить решение',
    _ => 'Готово',
  };

  Widget _budgetBody({required bool revision}) {
    final split = _split;
    final total = split?.fold<int>(0, (sum, value) => sum + value);
    final residual = total == null ? null : _snapshot.wallet[0] - total;
    final baseline = _snapshot.planVersions.isNotEmpty
        ? _snapshot.planVersions.first.split
        : _snapshot.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(
          revision ? 'Уточни решение' : 'Дай каждой монете направление',
          subtitle: revision
              ? 'Исходная версия останется в истории. Доступно в «Сейчас»: ${_snapshot.wallet[0]}.'
              : 'Доступно в «Сейчас»: ${_snapshot.wallet[0]} монет. План не переводит и не списывает деньги.',
        ),
        if (revision) ...[
          const SizedBox(height: 16),
          Surface(
            color: sage,
            child: Text(
              'Исходный план: забота ${baseline[0]}, '
              'желания ${baseline[1]}, '
              'накопления ${baseline[2]}.',
            ),
          ),
        ],
        const SizedBox(height: 18),
        _amountField('Забота', _care, '${widget.lessonId}-care'),
        const SizedBox(height: 12),
        _amountField('Желания', _wants, '${widget.lessonId}-wants'),
        const SizedBox(height: 12),
        _amountField('Накопления', _savings, '${widget.lessonId}-savings'),
        const SizedBox(height: 14),
        Surface(
          color: residual != null && residual < 0 ? peach : sage,
          child: Text(
            residual == null
                ? 'Свободный остаток: проверь суммы'
                : residual < 0
                ? 'Превышение: ${-residual} монет — такой план нельзя подтвердить'
                : 'Свободный остаток: $residual монет',
            key: const Key('plan-residual'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (revision) ...[
          const SizedBox(height: 18),
          Text(
            'Почему план изменился?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _choiceTile(
            'После дохода уточняю суммы',
            _reason == 'После дохода уточняю суммы',
            () => setState(() => _reason = 'После дохода уточняю суммы'),
          ),
          _choiceTile(
            'Откладываю желание и направляю деньги важнее',
            _reason == 'Откладываю желание и направляю деньги важнее',
            () => setState(
              () => _reason = 'Откладываю желание и направляю деньги важнее',
            ),
          ),
        ],
      ],
    );
  }

  Widget _amountField(
    String label,
    TextEditingController controller,
    String keyName,
  ) => TextField(
    key: Key(keyName),
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: '$label, монет'),
    onChanged: (_) => setState(() => _error = null),
  );

  Widget _goalsBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Heading(
        'Сравни все три мечты',
        subtitle:
            'В конверте «На мечту» ${_snapshot.wallet[1]} монет. Смена цели не уменьшит эту сумму.',
      ),
      const SizedBox(height: 16),
      for (final goal in goals)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            selected: _selectedGoal == goal.id,
            button: true,
            child: OutlinedButton(
              key: Key('goal-${goal.id}'),
              onPressed: () => setState(() => _selectedGoal = goal.id),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                backgroundColor: _selectedGoal == goal.id ? sage : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal.name),
                  const SizedBox(height: 4),
                  Text(
                    'Цена ${goal.price} · осталось ${(goal.price - _snapshot.wallet[1]).clamp(0, goal.price)}',
                    style: const TextStyle(fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ),
          ),
        ),
      Text(
        'Накопления после выбора: ${_snapshot.wallet[1]} монет',
        key: const Key('goal-savings-preserved'),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _transferBody() {
    final value = int.tryParse(_transfer.text) ?? 0;
    final safe = value.clamp(0, _snapshot.wallet[0]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading(
          'Посмотри оба результата',
          subtitle:
              'Сначала сравни мечту и запас в учебной копии. Настоящим станет только подтверждённый перевод.',
        ),
        const SizedBox(height: 16),
        _amountField('Сумма перевода', _transfer, 'S02-amount'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('target-dream'),
              label: const Text('В мечту'),
              selected: _transferTarget == 'dream',
              onSelected: (_) => setState(() => _transferTarget = 'dream'),
            ),
            ChoiceChip(
              key: const Key('target-reserve'),
              label: const Text('В запас'),
              selected: _transferTarget == 'reserve',
              onSelected: (_) => setState(() => _transferTarget = 'reserve'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Surface(
          color: sage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'УЧЕБНАЯ КОПИЯ · ОБА ВАРИАНТА',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'В мечту: ${_snapshot.wallet[1]} → ${_snapshot.wallet[1] + safe}',
              ),
              Text(
                'В запас: ${_snapshot.wallet[2]} → ${_snapshot.wallet[2] + safe}',
              ),
              Text(
                '«Сейчас»: ${_snapshot.wallet[0]} → ${_snapshot.wallet[0] - safe}',
              ),
              const SizedBox(height: 8),
              Text(
                'Общая сумма остаётся ${_snapshot.total}.',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _basketBody() {
    final total = (_food ? 10 : 0) + (_clean ? 5 : 0) + (_ball ? 15 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading(
          'Собери учебную корзину',
          subtitle:
              'Найди ровно две необходимые позиции. Это тренировка: 15 монет за корзину не спишутся.',
        ),
        const SizedBox(height: 12),
        _basketTile(
          'Корм',
          'Необходимое · 10',
          _food,
          (value) => _food = value,
        ),
        _basketTile(
          'Средства чистоты',
          'Необходимое · 5',
          _clean,
          (value) => _clean = value,
        ),
        _basketTile(
          'Разноцветный мяч',
          'Желание · 15',
          _ball,
          (value) => _ball = value,
        ),
        const SizedBox(height: 8),
        Text(
          'Учебная сумма: $total монет',
          key: const Key('basket-total'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Text(
          'Почему этот выбор разумный?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final option in const [
          'Корм и чистота нужны питомцу сегодня',
          'Эти упаковки самые яркие',
          'Я выбрал случайно',
        ])
          _choiceTile(
            option,
            _rationale == option,
            () => setState(() => _rationale = option),
          ),
        const SizedBox(height: 8),
        const Text(
          'Реальные покупки корма и чистоты подтверждаются отдельно.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          _snapshot.incomeAvailable
              ? 'После верного решения: доход за задание +30.'
              : 'Доход этого периода уже получен: задание завершится без новых монет.',
          style: const TextStyle(color: muted, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _basketTile(
    String title,
    String subtitle,
    bool value,
    void Function(bool value) assign,
  ) => CheckboxListTile(
    value: value,
    onChanged: (next) => setState(() {
      assign(next ?? false);
      _error = null;
    }),
    title: Text(title),
    subtitle: Text(subtitle),
    controlAffinity: ListTileControlAffinity.leading,
  );

  Widget _insufficientBody() {
    const price = 35;
    final localScenario = _snapshot.wallet[0] >= price;
    final current = localScenario ? 30 : _snapshot.wallet[0];
    final shortage = price - current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(
          'Проверь необязательную покупку',
          subtitle: localScenario
              ? 'В настоящем кошельке хватает денег, поэтому ниже честно показана учебная копия: 30 монет против цены 35.'
              : 'В настоящем «Сейчас» $current монет. Лежанка стоит 35 и относится к желаниям.',
        ),
        const SizedBox(height: 16),
        Surface(
          color: localScenario ? sage : peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localScenario ? 'УЧЕБНАЯ КОПИЯ' : 'НАСТОЯЩИЙ БАЛАНС',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Мягкая лежанка · желание · 35 монет'),
              Text('Доступно: $current монет'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!_purchaseAttempted)
          OutlinedButton(
            key: const Key('p06-attempt'),
            onPressed: () => setState(() {
              _purchaseAttempted = true;
              _error = null;
            }),
            child: const Text('Попробовать купить'),
          )
        else ...[
          Semantics(
            liveRegion: true,
            child: Surface(
              color: peach,
              child: Text(
                'Покупка не прошла: не хватает $shortage монет. Списано 0.',
                key: const Key('p06-shortage'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _choiceTile(
            'Отложить лежанку',
            _p06Resolution == 'defer',
            () => setState(() => _p06Resolution = 'defer'),
          ),
          _choiceTile(
            'Пересмотреть план',
            _p06Resolution == 'replan',
            () => setState(() => _p06Resolution = 'replan'),
          ),
        ],
      ],
    );
  }

  Widget _choiceTile(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          selected: selected,
          button: true,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              backgroundColor: selected ? sage : null,
            ),
            child: Text(label),
          ),
        ),
      );

  Widget _successBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Surface(
        color: sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _reward! > 0
                  ? 'Задание выполнено: +$_reward монет'
                  : 'Решение сохранено',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(_successExplanation),
            if (widget.lessonId == 'S02') ...[
              const SizedBox(height: 12),
              _transferReceipt(),
            ],
            if (_practice) ...[
              const SizedBox(height: 8),
              const Text(
                'Это была учебная копия. Основной кошелёк и план не изменились.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
      if (widget.onGo != null && widget.lessonId == 'S01') ...[
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('canon-next-step'),
          onPressed: () => widget.onGo!(_receipt!.nextTarget),
          child: Text(_receipt!.nextLabel),
        ),
      ],
      if (widget.onGo != null && widget.lessonId == 'P01') ...[
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => widget.onGo!('catalog'),
          child: const Text('К реальным покупкам'),
        ),
      ],
      if (widget.onGo != null &&
          {'B02', 'B04', 'S02', 'P06'}.contains(widget.lessonId)) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => widget.onGo!('budget'),
          child: const Text('Открыть бюджет'),
        ),
      ],
    ],
  );

  Widget _transferReceipt() {
    final receipt = _receipt!;
    const names = ['Сейчас', 'На мечту', 'Запас'];
    String delta(int value) => value > 0
        ? '+$value'
        : value < 0
        ? '−${-value}'
        : '0';
    return Column(
      key: const Key('canon-transfer-receipt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (receipt.practice)
          const Text('Основные конверты остались без изменений:'),
        for (var index = 0; index < names.length; index++)
          Text(
            '«${names[index]}»: ${receipt.before.wallet[index]} → '
            '${receipt.after.wallet[index]} '
            '(${delta(receipt.after.wallet[index] - receipt.before.wallet[index])})',
          ),
        const SizedBox(height: 8),
        Text('Всего: ${receipt.before.total} → ${receipt.after.total} монет.'),
        const Text('Перевод не создаёт доход.'),
        const Text('Сытость, радость и чистота от перевода не изменились.'),
      ],
    );
  }

  String get _transferExplanation {
    final receipt = _receipt!;
    if (receipt.practice) {
      return 'Учебный перевод проверен. Из основных конвертов списано 0 монет.';
    }
    if (!receipt.applied) {
      return 'Это задание уже выполнено. Новый перевод не выполнялся: списано 0 монет.';
    }
    final target = receipt.submission.transferTarget == 'dream' ? 1 : 2;
    final amount = receipt.after.wallet[target] - receipt.before.wallet[target];
    final name = target == 1 ? 'На мечту' : 'Запас';
    return 'Переведено $amount монет из «Сейчас» в «$name».';
  }

  String get _successExplanation => switch (widget.lessonId) {
    'B02' => 'Видимый остаток помогает не запланировать больше, чем доступно.',
    'B04' => 'Новая версия добавлена, а исходный план остался в истории.',
    'S01' => 'Цель выбрана. Уже отложенные монеты сохранились.',
    'S02' => _transferExplanation,
    'P01' =>
      _reward! > 0
          ? 'Учебная корзина стоила 15 и не была оплачена. Доход 30 начислен отдельно за выполненное задание.'
          : 'Корзина собрана верно. Доход этого периода уже был получен, поэтому новых монет нет.',
    'P06' => 'Лежанка не куплена, списано 0. К решению можно вернуться позже.',
    _ => '',
  };
}
