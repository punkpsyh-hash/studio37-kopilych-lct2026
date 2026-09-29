import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'cartoon_props.dart';
import 'game.dart';
import 'room_scene.dart';
import 'scene_bridge.dart';
import 'ui.dart';

class _JobPlacementSheet extends StatefulWidget {
  const _JobPlacementSheet({required this.job});
  final JobProgress job;

  @override
  State<_JobPlacementSheet> createState() => _JobPlacementSheetState();
}

class _JobPlacementSheetState extends State<_JobPlacementSheet> {
  JobPlacementOption? selected;

  @override
  Widget build(BuildContext context) {
    final source = selected;
    final options = source == null
        ? widget.job.placementSources
        : widget.job.placementTargets;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  source == null
                      ? 'Выбери вещь'
                      : 'Куда положить: ${source.label}?',
                  key: const ValueKey('job-placement-question'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in options) ...[
                OutlinedButton(
                  key: ValueKey(
                    'job-${source == null ? 'source' : 'target'}-${option.id}',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    if (source == null) {
                      setState(() => selected = option);
                    } else {
                      Navigator.of(context).pop((source.id, option.id));
                    }
                  },
                  child: Text(option.label, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(
                onPressed: () {
                  if (source == null) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => selected = null);
                  }
                },
                child: Text(
                  source == null
                      ? 'Вернуться в комнату'
                      : 'Выбрать другую вещь',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameHudGeometry {
  const GameHudGeometry({
    required this.landscape,
    required this.panelWidth,
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  final bool landscape;
  final double panelWidth, top, right, bottom, left;

  factory GameHudGeometry.resolve(
    Size size,
    EdgeInsets safePadding, {
    required bool accessible,
    bool activeMinigame = false,
  }) {
    final landscape = size.width > size.height;
    if (!landscape) {
      final safeHeight = math.max(
        1.0,
        size.height - safePadding.top - safePadding.bottom,
      );
      final compactTaskTop = math.max(
        .04,
        (safePadding.top + 12) / size.height,
      );
      final taskBottom = math.min(
        .45,
        (safePadding.bottom + 12 + safeHeight * .40) / size.height,
      );
      return GameHudGeometry(
        landscape: false,
        panelWidth: 0,
        top: accessible && activeMinigame
            ? compactTaskTop
            : accessible
            ? .38
            : .13,
        right: 0,
        bottom: accessible && activeMinigame
            ? taskBottom
            : accessible
            ? .40
            : .09,
        left: 0,
      );
    }
    final safeWidth = math.max(
      1.0,
      size.width - safePadding.left - safePadding.right,
    );
    final desiredPanel = (safeWidth * .30).clamp(160.0, 300.0);
    // Keep both actual covered sides at or below 36% of the full viewport.
    // This includes cutout padding and the 12dp floating gutter.
    final protocolPanelLimit = math.max(
      120.0,
      size.width * .36 - math.max(safePadding.left, safePadding.right) - 12,
    );
    final panelWidth = math.min(desiredPanel, protocolPanelLimit);
    return GameHudGeometry(
      landscape: true,
      panelWidth: panelWidth,
      top: 0,
      right: (safePadding.right + 12 + panelWidth) / size.width,
      bottom: 0,
      left: (safePadding.left + 12 + panelWidth) / size.width,
    );
  }
}

class HouseholdJobPicker extends StatelessWidget {
  const HouseholdJobPicker({
    super.key,
    required this.currentRoom,
    required this.incomeAvailable,
    required this.planConfirmed,
    required this.onSelected,
  });

  final String currentRoom;
  final bool incomeAvailable, planConfirmed;
  final ValueChanged<HouseholdJob> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: ListView(
        key: const ValueKey('job-picker'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Домашние дела',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                key: const ValueKey('job-picker-close'),
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const CozyIcon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            !planConfirmed
                ? 'Сначала составь план дня. Затем выбери любое дело: за первое выполненное дело или задание родители дадут 30 монет.'
                : incomeAvailable
                ? 'За первое выполненное дело или задание сегодня родители дадут 30 монет.'
                : 'Доход сегодня уже получен. Все дела доступны как тренировка без монет.',
          ),
          const SizedBox(height: 16),
          for (final room in HomeRoom.values) ...[
            Row(
              children: [
                CozyIcon(room.icon, size: 22),
                const SizedBox(width: 8),
                Text(
                  room.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (room.assetName == currentRoom) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: sage,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'ВЫ ЗДЕСЬ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            for (final job in householdJobs.values.where(
              (job) => job.room == room.assetName,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    key: ValueKey('job-picker-${job.id.toLowerCase()}'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelected(job),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const PropArt(CartoonProp.clipboard, size: 34),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  !planConfirmed
                                      ? 'Сначала план дня'
                                      : incomeAvailable
                                      ? 'Награда: 30 монет'
                                      : 'Тренировка · без монет',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            room.assetName == currentRoom
                                ? 'Начать'
                                : 'Перейти',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 4),
                          const CozyIcon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

/// Floating, native touch controls over the complete 3D room.
class GameHome extends StatelessWidget {
  const GameHome({
    super.key,
    required this.state,
    required this.scene,
    required this.ready,
    required this.busy,
    required this.onRoom,
    required this.onCare,
    required this.onLamp,
    required this.onPlan,
    required this.onMission,
    required this.onDream,
    required this.onNextDay,
    this.dish = const DishProgress(),
    this.onJob,
    this.onMenu,
    this.onShowJob,
    this.lessonIncomeAvailable,
    this.lessonWithoutReward = false,
    this.onDishStep,
    this.onCancelDish,
    this.onViewportInsets,
    this.job = const JobProgress(),
    this.jobId = 'J01',
    this.jobTitle = 'Помой посуду',
    this.jobRoom = 'kitchen',
    this.jobIncomeAvailable,
    this.onJobStep,
    this.onJobPlacement,
    this.onCancelJob,
    this.onWater,
    this.taskFeedback,
    this.onDismissFeedback,
    this.nextStepTitle,
    this.onNextStep,
    this.nextStepCollapsed = false,
    this.onToggleNextStep,
  });
  final GameState state;
  final Widget scene;
  final bool ready, busy;
  final ValueChanged<HomeRoom> onRoom;
  final VoidCallback onCare, onLamp, onPlan, onMission, onDream, onNextDay;
  final VoidCallback? onJob, onCancelDish, onMenu, onShowJob;
  final bool? lessonIncomeAvailable;
  final bool lessonWithoutReward;
  final ValueChanged<String>? onDishStep;
  final void Function(double top, double right, double bottom, double left)?
  onViewportInsets;
  final DishProgress dish;
  final JobProgress job;
  final String jobId, jobTitle, jobRoom;
  final bool? jobIncomeAvailable;
  final ValueChanged<String>? onJobStep;
  final void Function(String sourceId, String targetId)? onJobPlacement;
  final VoidCallback? onCancelJob;
  final VoidCallback? onWater;
  final String? taskFeedback;
  final VoidCallback? onDismissFeedback;
  final String? nextStepTitle;
  final VoidCallback? onNextStep;
  final bool nextStepCollapsed;
  final VoidCallback? onToggleNextStep;
  bool get _taskActive => dish.active || job.active;

  Future<void> _choosePlacement(BuildContext context) async {
    final choice = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _JobPlacementSheet(job: job),
    );
    if (context.mounted && choice != null) {
      onJobPlacement?.call(choice.$1, choice.$2);
    }
  }

  Widget _jobControls(BuildContext context) {
    final saving = job.stage == 'ready' || job.stage == 'awaiting_ack';
    final placement = {'J02', 'J04'}.contains(job.jobId);
    final instruction = saving
        ? 'Сохраняем результат…'
        : switch (job.nextStep) {
            'sort' =>
              job.jobId == 'J04'
                  ? 'Найди контейнер с таким же знаком.'
                  : 'Выбери любую вещь и положи на её место.',
            'fold' => 'Сложи полотенце по линии.',
            'shelf' => 'Положи полотенце на полку.',
            'wipe' => 'Протри пыль салфеткой.',
            'sweep' => 'Собери мусор веником в совок.',
            'empty' => 'Высыпь мусор из совка.',
            'put_away' =>
              job.jobId == 'J06'
                  ? job.completed == 4
                        ? 'Верни веник на место.'
                        : 'Верни совок на место.'
                  : 'Верни салфетку на место.',
            _ => job.title,
          };
    final button = switch (job.nextStep) {
      'sort' => 'Выбрать вещь и место',
      'fold' => 'Сложить полотенце',
      'shelf' => 'Положить на полку',
      'wipe' => 'Протереть участок',
      'sweep' => 'Подмести участок',
      'empty' => 'Опустошить совок',
      'put_away' =>
        job.jobId == 'J06'
            ? job.completed == 4
                  ? 'Убрать веник'
                  : 'Убрать совок'
            : 'Убрать салфетку',
      _ => 'Готово',
    };
    return _pill(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (job.feedbackMessage != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                job.feedbackMessage!,
                key: const ValueKey('job-feedback'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8A3E2D),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${job.completed} из ${job.total}',
            key: const ValueKey('job-progress'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('job-cancel'),
                onPressed: saving || busy ? null : onCancelJob,
                child: const Text('Выйти'),
              ),
              FilledButton(
                key: const ValueKey('job-step'),
                onPressed:
                    saving || busy || job.placementBusy || job.nextStep == null
                    ? null
                    : placement
                    ? job.placementSources.isEmpty ||
                              job.placementTargets.isEmpty ||
                              onJobPlacement == null
                          ? null
                          : () => _choosePlacement(context)
                    : () => onJobStep?.call(job.nextStep!),
                child: Text(button),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(
    Widget child, {
    EdgeInsetsGeometry? padding,
    bool accent = false,
  }) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: accent
            ? const [Color(0xFFFFF3D6), Color(0xFFF9D9A0)]
            : const [Color(0xFFFFFBEF), Color(0xFFF4E4C4)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: accent ? const Color(0xFFE88B2E) : const Color(0xFFB59B73),
        width: accent ? 2 : 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: accent ? const Color(0xFFC96F14) : const Color(0xFFAC8B5C),
          offset: const Offset(0, 2),
        ),
        const BoxShadow(
          color: Color(0x265C4022),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    ),
  );

  void _showPetCard(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            CozyImage(
              const [
                'kitten-face',
                'puppy-face',
                'hamster-face',
              ][state.species],
              size: 56,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(state.name ?? defaultNames[state.species])),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.adoptedOn.isEmpty
                  ? speciesNames[state.species]
                  : '${speciesNames[state.species]} · стал другом ${state.adoptedOn}',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) ...[
              Text(
                '${['Сытость', 'Радость', 'Чистота'][i]} · ${state.needs[i]} из 100',
              ),
              LinearProgressIndicator(value: state.needs[i] / 100),
              const SizedBox(height: 8),
            ],
            Text('Сейчас день ${state.day}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showNeedHelp(BuildContext context, int index) {
    final labels = ['Сытость', 'Радость', 'Чистота'];
    final places = ['на кухне', 'в гостиной', 'в ванной'];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(labels[index]),
        content: Text(
          '${state.needs[index]} из 100. Пополни этот показатель ${places[index]}, нажав на предмет или кнопку действия.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Widget _status(BuildContext context, {bool accessible = false}) {
    final identity = _pill(
      InkWell(
        key: const ValueKey('scene-pet-profile'),
        onTap: () => _showPetCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.name ?? defaultNames[state.species],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Text(
              'День ${state.day}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    final balance = _pill(
      InkWell(
        onTap: busy || _taskActive ? null : onPlan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Semantics(
              label: 'Сейчас ${state.wallet[0]} монет',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Coins(state.wallet[0]),
              ),
            ),
            Text(
              'Запас: ${state.wallet[2]} монет',
              key: const ValueKey('scene-reserve'),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    final dream = _pill(
      Semantics(
        button: true,
        enabled: !busy && !_taskActive,
        label:
            'Текущая цель: ${state.goal.name}. Накоплено ${state.wallet[1]} из ${state.goal.price} монет',
        excludeSemantics: true,
        child: InkWell(
          onTap: busy || _taskActive ? null : onDream,
          child: Row(
            children: [
              const PropArt(CartoonProp.house, size: 28),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Цель: ${state.goal.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${state.wallet[1]} / ${state.goal.price}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final needs = [
      for (var i = 0; i < 3; i++)
        Semantics(
          label:
              '${['Сытость', 'Радость', 'Чистота'][i]} ${state.needs[i]} из 100',
          child: _pill(
            InkWell(
              onTap: () => _showNeedHelp(context, i),
              child: Column(
                children: [
                  PropArt(
                    [CartoonProp.bowl, CartoonProp.heart, CartoonProp.soap][i],
                    size: 28,
                  ),
                  Text(
                    '${state.needs[i]}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accessible)
          Wrap(spacing: 8, runSpacing: 8, children: [identity, balance])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: identity),
              const Spacer(),
              balance,
            ],
          ),
        const SizedBox(height: 8),
        if (accessible) ...[
          dream,
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: needs),
        ] else
          Row(
            children: [
              Expanded(child: dream),
              const SizedBox(width: 8),
              for (final need in needs)
                Padding(padding: const EdgeInsets.only(left: 5), child: need),
            ],
          ),
      ],
    );
  }

  // 29.09: кнопка света убрана по решению владельца.
  Widget _lampButton(bool enabled) => const SizedBox.shrink();

  // ignore: unused_element
  Widget _lampButtonLegacy(bool enabled) => _pill(
    Semantics(
      key: const ValueKey('scene-lamp-semantics'),
      toggled: state.currentLampOn,
      child: IconButton(
        key: const ValueKey('scene-lamp'),
        onPressed: enabled ? onLamp : null,
        tooltip: state.currentLampOn
            ? 'Выключить светильник'
            : 'Включить светильник',
        style: IconButton.styleFrom(
          backgroundColor: state.currentLampOn ? sage : cream,
          disabledBackgroundColor: cream,
          side: BorderSide(
            color: !enabled
                ? const Color(0xFFAAA695)
                : state.currentLampOn
                ? blue
                : caramel,
            width: state.currentLampOn ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Opacity(
          opacity: !enabled
              ? .45
              : state.currentLampOn
              ? 1
              : .65,
          child: const PropArt(CartoonProp.lamp, size: 28),
        ),
      ),
    ),
    padding: EdgeInsets.zero,
  );

  Widget _controls(HomeRoom room) {
    final enabled = ready && !busy;
    final price = state.careCost(switch (room) {
      HomeRoom.kitchen => 0,
      HomeRoom.bathroom => 2,
      _ => 1,
    });
    final care = room == HomeRoom.bathroom && state.species == 2
        ? 'Песочная ванночка'
        : room.actionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('scene-care'),
                onPressed: enabled ? onCare : null,
                icon: CozyIcon(room.icon, size: 20),
                label: Text(
                  price == 0 ? '$care · бесплатно' : '$care · $price монет',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...[const SizedBox(width: 8), _lampButton(enabled)],
          ],
        ),
        if (room == HomeRoom.kitchen || onJob != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _pill(
              InkWell(
                key: const ValueKey('scene-job'),
                onTap: enabled ? onJob : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const PropArt(CartoonProp.clipboard, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (jobIncomeAvailable ?? state.incomeAvailable)
                              ? '$jobTitle · Награда: 30 монет'
                              : '$jobTitle · Тренировка · без монет',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const CozyIcon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final destination in HomeRoom.values)
              ChoiceChip(
                key: ValueKey('scene-room-${destination.assetName}'),
                label: Text(destination.label),
                backgroundColor: cream,
                selectedColor: const Color(0xFFDCE6D4),
                selected: room == destination,
                onSelected: enabled
                    ? (_) {
                        if (room != destination) onRoom(destination);
                      }
                    : null,
                showCheckmark: false,
              ),
          ],
        ),
        _pill(
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              TextButton(
                onPressed: busy ? null : onPlan,
                child: const Text('План'),
              ),
              TextButton(
                key: const ValueKey('scene-mission'),
                onPressed: busy ? null : onMission,
                child: Text(
                  (lessonIncomeAvailable ?? state.incomeAvailable)
                      ? 'Задание · Награда: 30 монет'
                      : lessonWithoutReward
                      ? 'Задание · Без награды'
                      : 'Задание · Тренировка · без монет',
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(
                onPressed: busy ? null : onNextDay,
                child: const Text('Итоги дня'),
              ),
            ],
          ),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _dishControls() {
    final awaiting = dish.stage == 'awaiting_ack';
    final step = switch (dish.stage) {
      'scrub' => 'scrub',
      'rinse' => 'rinse',
      _ => 'finish',
    };
    final instruction = switch (dish.stage) {
      'scrub' => 'Намыль тарелку',
      'rinse' => 'Смой пену',
      'water_off' => 'Закрой кран',
      _ => 'Сохраняем результат…',
    };
    final remaining = dish.coverage?.remainingSpots ?? (6 - dish.cleaned);
    final progress = switch (dish.stage) {
      'scrub' when remaining <= 0 => 'Все пятна намылены',
      'scrub' when remaining == 1 => 'Осталось одно пятно',
      'scrub' => 'Осталось пятен: $remaining',
      'rinse' when dish.coverage != null =>
        'Смыто ${(dish.coverage!.rinse * 100).round()}%',
      'rinse' => 'Пена готова к смыванию',
      'water_off' => 'Тарелка чистая',
      _ => 'Сохраняем результат…',
    };
    return _pill(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (dish.feedbackMessage != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                dish.feedbackMessage!,
                key: const ValueKey('dish-feedback'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8A3E2D),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(progress, key: const ValueKey('dish-progress')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('dish-cancel'),
                onPressed: awaiting || busy ? null : onCancelDish,
                child: const Text('Выйти'),
              ),
              FilledButton(
                key: const ValueKey('dish-step'),
                onPressed: awaiting || busy
                    ? null
                    : () => onDishStep?.call(step),
                child: Text(switch (step) {
                  'scrub' => 'Намылить пятно',
                  'rinse' => 'Смыть пену',
                  _ => 'Закрыть кран',
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactStatus(
    BuildContext context, {
    bool narrow = false,
    bool largeText = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: largeText
              ? 190
              : narrow
              ? 104
              : 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _pill(
                    IconButton(
                      key: const ValueKey('scene-pet-profile'),
                      onPressed: () => _showPetCard(context),
                      tooltip: 'Питомец и его показатели',
                      icon: CozyImage(
                        const [
                          'kitten-face',
                          'puppy-face',
                          'hamster-face',
                        ][state.species],
                        size: 32,
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: 42,
                        height: 42,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _pill(
                      Semantics(
                        button: true,
                        label:
                            'Всего ${state.total} монет. Сейчас ${state.wallet[0]}, на мечту ${state.wallet[1]}, запас ${state.wallet[2]}',
                        child: InkWell(
                          key: const ValueKey('scene-budget'),
                          onTap: busy || _taskActive ? null : onPlan,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const PropArt(CartoonProp.coin, size: 19),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      '${state.total}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'В запасе ${state.wallet[2]}',
                                key: const ValueKey('scene-reserve'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _pill(
                Text(
                  '${state.name ?? defaultNames[state.species]} · День ${state.day}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ],
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: narrow ? 108 : 140,
                  child: _pill(
                    Semantics(
                      button: true,
                      enabled: !busy && !_taskActive,
                      label:
                          'Текущая цель: ${state.goal.name}. Накоплено ${state.wallet[1]} из ${state.goal.price} монет',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: busy || _taskActive ? null : onDream,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.savings_rounded,
                              size: 21,
                              color: Color(0xFFAF6B34),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.goal.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${state.wallet[1]}/${state.goal.price}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'Ещё ${math.max(0, state.goal.price - state.wallet[1])}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _pill(
                  IconButton(
                    key: const ValueKey('scene-menu'),
                    onPressed: _taskActive || busy ? null : onMenu,
                    tooltip: 'Меню',
                    icon: const PropArt(CartoonProp.menu, size: 36),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                    child: Semantics(
                      label:
                          '${['Сытость', 'Радость', 'Чистота'][i]} ${state.needs[i]} из 100',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _pill(
                          InkWell(
                            onTap: () => _showNeedHelp(context, i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PropArt(
                                  [
                                    CartoonProp.bowl,
                                    CartoonProp.heart,
                                    CartoonProp.soap,
                                  ][i],
                                  size: 23,
                                ),
                                const SizedBox(height: 3),
                                SizedBox(
                                  width: 24,
                                  height: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: state.needs[i] / 100,
                                      color: const [
                                        Color(0xFFB67829),
                                        Color(0xFFB7474A),
                                        Color(0xFF417E9A),
                                      ][i],
                                      backgroundColor: const Color(0xFFDECFB1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockButton({
    required Key key,
    required String label,
    required CartoonProp icon,
    required VoidCallback? action,
    String? detail,
    String? semanticLabel,
    bool selected = false,
  }) => Expanded(
    child: Semantics(
      selected: selected,
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      onTap: semanticLabel != null ? action : null,
      enabled: action != null,
      child: InkWell(
        key: key,
        onTap: action,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? const [Color(0xFFF7F8E9), Color(0xFFD5E4B5)]
                    : const [Color(0xFFFFFCF1), Color(0xFFF2DEB9)],
              ),
              border: Border.all(
                color: selected
                    ? const Color(0xFF5F823B)
                    : const Color(0xFF8C6138),
                width: selected ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? const Color(0x805EAB3B)
                      : const Color(0x8859351A),
                  blurRadius: selected ? 9 : 5,
                  spreadRadius: selected ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // Large accessibility text must shrink inside the fixed-height
            // room button instead of overflowing it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PropArt(icon, size: 29),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 8,
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
  );

  Widget _compactControls(HomeRoom room, {bool showRooms = true}) {
    final enabled = ready && !busy;
    final jobDock = onJob != null || room == HomeRoom.kitchen;
    final incomeAvailable = jobDock
        ? (jobIncomeAvailable ?? state.incomeAvailable)
        : (lessonIncomeAvailable ?? state.incomeAvailable);
    final rewardDetail = incomeAvailable
        ? '30 монет'
        : !jobDock && lessonWithoutReward
        ? 'Без награды'
        : 'Без монет';
    final rewardSemantics = incomeAvailable
        ? 'Награда: 30 монет'
        : !jobDock && lessonWithoutReward
        ? 'Без награды'
        : 'Тренировка · без монет';
    final jobLabel = room == HomeRoom.kitchen
        ? 'Посуда'
        : onJob != null
        ? 'Дела'
        : jobDock
        ? 'Посуда'
        : 'Задание';
    final care = room == HomeRoom.bathroom && state.species == 2
        ? 'Песочная ванночка'
        : room.actionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: showRooms ? 150 : 122,
              child: _pill(
                TextButton.icon(
                  key: const ValueKey('scene-care'),
                  onPressed: enabled ? onCare : null,
                  icon: PropArt(switch (room) {
                    HomeRoom.living => CartoonProp.ball,
                    HomeRoom.kitchen => CartoonProp.bowl,
                    HomeRoom.bathroom => CartoonProp.soap,
                  }, size: 22),
                  label: Text(
                    room.price == 0 ? care : '$care · ${room.price}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
                padding: EdgeInsets.zero,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 116,
              child: Semantics(
                button: true,
                enabled: enabled,
                label:
                    '${room == HomeRoom.kitchen ? 'Посуда и другие дела' : jobLabel}. $rewardSemantics',
                excludeSemantics: true,
                child: _pill(
                  TextButton.icon(
                    key: ValueKey(jobDock ? 'scene-job' : 'scene-mission'),
                    onPressed: enabled
                        ? (onJob ??
                              (room == HomeRoom.kitchen ? null : onMission))
                        : null,
                    icon: const PropArt(CartoonProp.clipboard, size: 20),
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jobLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          rewardDetail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
        if (showRooms) ...[
          const SizedBox(height: 8),
          _pill(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final destination in HomeRoom.values)
                  _dockButton(
                    key: ValueKey('scene-room-${destination.assetName}'),
                    label: destination.label,
                    icon: switch (destination) {
                      HomeRoom.living => CartoonProp.sofa,
                      HomeRoom.kitchen => CartoonProp.bowl,
                      HomeRoom.bathroom => CartoonProp.bath,
                    },
                    selected: room == destination,
                    action: enabled && destination != room
                        ? () => onRoom(destination)
                        : null,
                  ),
              ],
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      ],
    );
  }

  Widget _portraitRoomStrip(HomeRoom room) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final destination in HomeRoom.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Semantics(
            button: true,
            selected: room == destination,
            label: 'Комната ${destination.label}',
            enabled: ready && !busy && room != destination,
            child: InkWell(
              key: ValueKey('scene-room-${destination.assetName}'),
              onTap: ready && !busy && room != destination
                  ? () => onRoom(destination)
                  : null,
              borderRadius: BorderRadius.circular(18),
              child: _pill(
                SizedBox(
                  width: 54,
                  height: 49,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PropArt(switch (destination) {
                        HomeRoom.living => CartoonProp.sofa,
                        HomeRoom.kitchen => CartoonProp.bowl,
                        HomeRoom.bathroom => CartoonProp.bath,
                      }, size: 25),
                      Text(
                        destination.label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                padding: EdgeInsets.zero,
                accent: room == destination,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _nextStep({bool accessible = false}) {
    if (_taskActive) return const SizedBox.shrink();
    if (nextStepTitle?.startsWith('Сравнить три мечты') ?? false) {
      return const SizedBox.shrink();
    }
    final hasStoryStep = nextStepTitle != null && onNextStep != null;
    final needsPlan = !state.planConfirmed;
    final showJob =
        !hasStoryStep &&
        !needsPlan &&
        (jobIncomeAvailable ?? state.incomeAvailable);
    if (!hasStoryStep &&
        !needsPlan &&
        !showJob &&
        state.planVersions.length > 1) {
      return const SizedBox.shrink();
    }
    final title = Text(
      hasStoryStep
          ? nextStepTitle!
          : needsPlan
          ? 'Спланируем игровой день'
          : showJob
          ? '${HomeRoom.values.firstWhere((r) => r.assetName == jobRoom).label} · $jobTitle'
          : 'Доход получен · уточни план',
      maxLines: accessible ? 3 : 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    );
    final button = TextButton(
      key: const ValueKey('scene-show-next'),
      onPressed: busy || !ready
          ? null
          : hasStoryStep
          ? onNextStep
          : showJob
          ? onShowJob
          : onPlan,
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: const Text('Показать'),
    );
    // Свёрнутый вид: подсказка не висит над сценой постоянно — по желанию
    // ребёнка пилюля уходит в компактный значок и возвращается по тапу.
    if (nextStepCollapsed && onToggleNextStep != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _pill(
            IconButton(
              key: const ValueKey('scene-show-next-collapsed'),
              tooltip: 'Показать подсказку: ${title.data}',
              onPressed: onToggleNextStep,
              icon: const CozyIcon(Icons.flag_rounded, size: 24),
            ),
            padding: EdgeInsets.zero,
            accent: true,
          ),
        ),
      );
    }
    final collapse = onToggleNextStep == null
        ? const SizedBox.shrink()
        : IconButton(
            key: const ValueKey('scene-hide-next'),
            tooltip: 'Скрыть подсказку',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleNextStep,
            icon: const CozyIcon(Icons.close_rounded, size: 18),
          );
    return TweenAnimationBuilder<double>(
      key: ValueKey('scene-step-${nextStepTitle ?? title.data}'),
      tween: Tween(begin: .94, end: 1),
      duration: state.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _pill(
          accessible
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: title),
                        collapse,
                      ],
                    ),
                    button,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    button,
                    collapse,
                  ],
                ),
          padding: const EdgeInsets.only(left: 12, right: 1),
          accent: true,
        ),
      ),
    );
  }

  Widget _feedback() {
    if (taskFeedback == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        liveRegion: true,
        child: _pill(
          Row(
            children: [
              const PropArt(CartoonProp.heart, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  taskFeedback!,
                  key: const ValueKey('job-result'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: const ValueKey('job-result-close'),
                tooltip: 'Закрыть сообщение',
                onPressed: onDismissFeedback,
                icon: const CozyIcon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room = HomeRoom.values.firstWhere(
        (r) => r.assetName == state.currentRoom,
      );
      final accessible =
          constraints.maxHeight < 520 ||
          MediaQuery.textScalerOf(context).scale(14) > 22;
      final geometry = GameHudGeometry.resolve(
        constraints.biggest,
        MediaQuery.paddingOf(context),
        accessible: accessible,
        activeMinigame: _taskActive,
      );
      final landscape = geometry.landscape;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onViewportInsets?.call(
          geometry.top,
          geometry.right,
          geometry.bottom,
          geometry.left,
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: scene),
          SafeArea(
            child: landscape
                ? LayoutBuilder(
                    builder: (context, safe) {
                      final panelWidth = geometry.panelWidth;
                      if (safe.maxWidth >= 700) {
                        final actionsWidth = math.min(
                          320.0,
                          safe.maxWidth * .40,
                        );
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(14) > 22;
                        // При крупном тексте кнопка «Показать» шире 220 —
                        // даём пилюле шаг и вертикальную раскладку.
                        final stepWidth = largeText ? 300.0 : 220.0;
                        return Stack(
                          children: [
                            Positioned(
                              top: 8,
                              left: 12,
                              right: 12,
                              child: SizedBox(
                                key: const ValueKey('scene-landscape-status'),
                                child: _compactStatus(
                                  context,
                                  largeText: largeText,
                                ),
                              ),
                            ),
                            if (!_taskActive)
                              Positioned(
                                top: 100,
                                left: 12,
                                width: stepWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _nextStep(accessible: largeText),
                                    _feedback(),
                                  ],
                                ),
                              ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              width: actionsWidth,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: math.max(48, safe.maxHeight - 125),
                                ),
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'scene-landscape-actions',
                                  ),
                                  child: job.active
                                      ? _jobControls(context)
                                      : dish.active
                                      ? _dishControls()
                                      : _compactControls(room),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 244,
                              right: actionsWidth + 24,
                              child: const IgnorePointer(
                                child: SizedBox(
                                  key: ValueKey('scene-open-center'),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return Stack(
                        children: [
                          Positioned(
                            top: 12,
                            bottom: 12,
                            left: 12,
                            width: panelWidth,
                            child: ListView(
                              key: const ValueKey('scene-landscape-status'),
                              padding: EdgeInsets.zero,
                              children: [
                                _status(context, accessible: true),
                                _nextStep(accessible: true),
                                _feedback(),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 12,
                            bottom: 12,
                            right: 12,
                            width: panelWidth,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SingleChildScrollView(
                                key: const ValueKey('scene-landscape-actions'),
                                child: job.active
                                    ? _jobControls(context)
                                    : dish.active
                                    ? _dishControls()
                                    : _controls(room),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: panelWidth + 24,
                            right: panelWidth + 24,
                            child: const IgnorePointer(
                              child: SizedBox(
                                key: ValueKey('scene-open-center'),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : accessible
                ? LayoutBuilder(
                    builder: (context, safe) => Stack(
                      children: [
                        if (!_taskActive)
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 12,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: safe.maxHeight * .38,
                              ),
                              child: ListView(
                                key: const ValueKey('scene-status-scroll'),
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  _status(context, accessible: true),
                                  _nextStep(accessible: true),
                                  _feedback(),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: safe.maxHeight * .40,
                            ),
                            child: ListView(
                              key: const ValueKey('scene-action-scroll'),
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: [
                                job.active
                                    ? _jobControls(context)
                                    : dish.active
                                    ? _dishControls()
                                    : _controls(room),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: _taskActive ? 12 : safe.maxHeight * .38 + 12,
                          bottom: safe.maxHeight * .40 + 12,
                          left: 0,
                          right: 0,
                          child: const IgnorePointer(
                            child: SizedBox(key: ValueKey('scene-open-center')),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: _compactStatus(
                          context,
                          narrow: constraints.maxWidth < 350,
                        ),
                      ),
                      if (!_taskActive)
                        Positioned(
                          top: 126,
                          left: 12,
                          width: math.min(220, constraints.maxWidth * .62),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [_nextStep(), _feedback()],
                          ),
                        ),
                      if (!_taskActive)
                        Positioned(
                          top: 132,
                          right: 12,
                          child: _portraitRoomStrip(room),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: job.active
                            ? _jobControls(context)
                            : dish.active
                            ? _dishControls()
                            : _compactControls(room, showRooms: false),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
