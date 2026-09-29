import 'package:flutter/material.dart';
import 'dart:math';

import 'finance_intro.dart';
import 'game.dart';
import 'scene_bridge.dart';
import 'shared_room.dart';
import 'ui.dart';

class AdoptionPage extends StatefulWidget {
  const AdoptionPage({super.key, required this.busy, required this.onStart});
  final bool busy;
  final Future<bool> Function(
    int species,
    int color,
    int accessory,
    String name,
  )
  onStart;

  @override
  State<AdoptionPage> createState() => _AdoptionPageState();
}

class _AdoptionPageState extends State<AdoptionPage> {
  static const _coatNames = [
    ['Рыжий', 'Серебристый полосатый', 'Кремовый'],
    ['Медовый', 'Чёрно-белый', 'Шоколадный'],
    ['Золотистый', 'Кремовый', 'Серо-белый'],
  ];
  static const _coatColors = [
    [Color(0xFFD98335), Color(0xFFA7ADB3), Color(0xFFEAD2A0)],
    [Color(0xFFC18B4F), Color(0xFF414447), Color(0xFF825330)],
    [Color(0xFFE4B851), Color(0xFFEDDCB1), Color(0xFFA7ADB3)],
  ];
  int? species;
  int color = 0;
  bool ready = false;
  final name = TextEditingController();
  final _random = Random();
  static const _suggestedNames = [
    ['Персик', 'Рыжик', 'Пушок', 'Тиша', 'Искорка'],
    ['Бублик', 'Дружок', 'Шарик', 'Боня', 'Чип'],
    ['Плюш', 'Хома', 'Пончик', 'Сёма', 'Крош'],
  ];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Map<String, Object?> get _sceneState => {
    'mode': 'adoption',
    'adoptionOpen': species != null,
    'room': 'living',
    'species': ['kitten', 'puppy', 'hamster'][species ?? 0],
    'color': 'fur_${(color + 1).toString().padLeft(2, '0')}',
    'wearable': null,
    'stage': 1,
    'owned': <String>[],
    'purchased': <String>[],
    'lampOn': true,
    'reducedMotion': MediaQuery.of(context).disableAnimations,
    'busy': widget.busy,
  };

  Future<void> _showHint() => showFinanceIntro(context);

  Widget _pill({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFCF2), Color(0xFFF2DFC0)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Color(0xFFB99568), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x34543A20),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: child,
    ),
  );

  Widget _speciesChoice() => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 8.0;
      final itemWidth = (constraints.maxWidth - spacing * 2) / 3;
      return Wrap(
        spacing: spacing,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < speciesNames.length; i++)
            SizedBox(
              width: itemWidth,
              child: Semantics(
                selected: species == i,
                button: true,
                child: Material(
                  color: species == i
                      ? sage.withValues(alpha: .96)
                      : cream.withValues(alpha: .92),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: species == i ? blue : const Color(0xFFE0C9A5),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('adopt-species-$i'),
                    onTap: widget.busy
                        ? null
                        : () {
                            if (species == i) return;
                            setState(() {
                              species = i;
                              color = 0;
                              ready = false;
                            });
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CozyImage(
                            const [
                              'kitten-face',
                              'puppy-face',
                              'hamster-face',
                            ][i],
                            size: 25,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            speciesNames[i],
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _coatChoice() => Wrap(
    spacing: 8,
    runSpacing: 6,
    alignment: WrapAlignment.center,
    children: [
      for (var i = 0; i < 3; i++)
        ChoiceChip(
          key: ValueKey('adopt-coat-$i'),
          label: Text(
            _coatNames[species ?? 0][i],
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          avatar: CircleAvatar(
            radius: 8,
            backgroundColor: _coatColors[species ?? 0][i],
          ),
          selected: color == i,
          visualDensity: VisualDensity.compact,
          onSelected: widget.busy
              ? null
              : (_) {
                  if (color == i) return;
                  setState(() {
                    color = i;
                    ready = false;
                  });
                },
        ),
    ],
  );

  Widget _actionButtons() {
    final start = FilledButton.icon(
      key: const ValueKey('adopt-start'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: widget.busy || !ready
          ? null
          : () {
              FocusManager.instance.primaryFocus?.unfocus();
              widget.onStart(species!, color, 0, name.text);
            },
      icon: widget.busy
          ? const SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const CozyIcon(Icons.favorite_rounded, size: 19),
      label: const Text(
        'Это мой друг!',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
    return SizedBox(width: double.infinity, child: start);
  }

  Widget _controls(double maxHeight) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: _pill(
          key: ValueKey(
            species == null ? 'adopt-choose-stage' : 'adopt-personalize-stage',
          ),
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight * .46),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Кто в коробке?',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  _speciesChoice(),
                  if (species != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('adopt-back'),
                        onPressed: widget.busy
                            ? null
                            : () => setState(() {
                                species = null;
                                ready = false;
                              }),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Назад к коробке'),
                      ),
                    ),
                    _coatChoice(),
                    const SizedBox(height: 6),
                    TextField(
                      controller: name,
                      maxLength: 18,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        labelText: 'Имя друга',
                        hintText: defaultNames[species!],
                        suffixIcon: IconButton(
                          key: const ValueKey('adopt-random-name'),
                          tooltip: 'Предложить другое имя',
                          onPressed: widget.busy
                              ? null
                              : () {
                                  final names = _suggestedNames[species!];
                                  final options = names
                                      .where(
                                        (candidate) => candidate != name.text,
                                      )
                                      .toList();
                                  name.text =
                                      options[_random.nextInt(options.length)];
                                },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _actionButtons(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: species == null
              ? 'Коробка ждёт твоего выбора'
              : '${speciesNames[species!]}, ${_coatNames[species!][color]}',
          child: SharedRoom(
            key: const ValueKey('adoption-room'),
            sceneState: _sceneState,
            soundEnabled: true,
            onReadyChanged: (value) {
              if (mounted && ready != value) setState(() => ready = value);
            },
            onAction: (_) async => const SceneActionResult(false),
          ),
        ),
        if (species != null && !ready)
          Center(
            child: IgnorePointer(
              child: _pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CozyImage(
                      const [
                        'kitten-face',
                        'puppy-face',
                        'hamster-face',
                      ][species!],
                      size: 72,
                    ),
                    const SizedBox(width: 8),
                    const Text('Знакомимся…'),
                  ],
                ),
              ),
            ),
          ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _pill(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CozyIcon(
                                    Icons.pets_rounded,
                                    color: blue,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      species == null
                                          ? 'Кто в коробке?'
                                          : 'Вот и твой друг!',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _pill(
                            padding: EdgeInsets.zero,
                            child: IconButton(
                              key: const ValueKey('adopt-hint'),
                              onPressed: _showHint,
                              tooltip: 'Как играть',
                              icon: const Icon(
                                Icons.help_outline_rounded,
                                color: blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _controls(constraints.maxHeight),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
