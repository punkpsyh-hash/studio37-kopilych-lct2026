import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'adult_page.dart';
import 'album_page.dart';
import 'adoption_page.dart';
import 'art.dart';
import 'budget_page.dart';
import 'controller.dart';
import 'content.dart';
import 'game.dart';
import 'game_home.dart';
import 'mission_page.dart';
import 'meshy_pet_view.dart';
import 'music.dart';
import 'onboarding.dart';
import 'room_scene.dart';
import 'ui.dart';
import 'story.dart';
import 'story_page.dart';
import 'scene_bridge.dart';
import 'shared_room.dart';
import 'scene_preview_page.dart';
import 'period_review.dart';
import 'finance_intro.dart';
import 'canon_lesson.dart';
import 'canon_lesson_page.dart';
import 'catalog_page.dart';

class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.controller,
    this.useMeshyModels = true,
    this.homeMusic,
  });
  final GameController controller;
  final bool useMeshyModels;
  final HomeMusic? homeMusic;
  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> with WidgetsBindingObserver {
  int tab = 0, reaction = 0;
  HomeRoom room = HomeRoom.living;
  PetAction petAction = PetAction.idle;
  final _sceneKey = GlobalKey<SharedRoomState>();
  bool _sceneReady = false;
  int? _soundVolumeDraft;
  int? _musicVolumeDraft;
  late final HomeMusic _music;
  late final Future<bool> _musicAvailable;
  bool _musicHomeVisible = false;
  bool _musicSyncScheduled = false;
  bool _firstHomeFallbackShown = false;
  ({bool enabled, int volume, bool homeVisible, bool minigameActive})?
  _lastMusicConfig;
  DishProgress _dish = const DishProgress();
  JobProgress _job = const JobProgress();
  DateTime? _dishStartedAt, _jobStartedAt;
  bool _dishStartedHappy = false, _jobStartedHappy = false;
  String? _selectedJobId, _taskFeedback;
  Timer? _feedbackTimer;
  String? _nextStepKey;
  bool _nextStepCollapsed = false;
  Timer? _hintTimer;
  Timer? _needsTimer;
  String? _catalogCareIntent;
  GameController get c => widget.controller;
  GameState get s => c.state!;
  @override
  void initState() {
    super.initState();
    _music = widget.homeMusic ?? HomeMusic();
    _musicAvailable = _hasBundledMusic();
    WidgetsBinding.instance.addObserver(this);
    if (c.loginBonusAwarded > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLoginBonus());
    }
    _needsTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final game = c.state;
      if (mounted &&
          !c.busy &&
          game != null &&
          game.needsResume(DateTime.now())) {
        unawaited(_resumeAndNotify());
      }
    });
  }

  Future<bool> _hasBundledMusic() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().contains(homeMusicAsset);
    } catch (_) {
      return false;
    }
  }

  void _scheduleMusicSync(bool routeCurrent) {
    _musicHomeVisible = routeCurrent && tab == 0 && c.state?.name != null;
    if (_musicSyncScheduled) return;
    _musicSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _musicSyncScheduled = false;
      if (mounted) _configureMusic();
    });
  }

  void _configureMusic({bool force = false}) {
    final game = c.state;
    final config = (
      enabled: game?.musicEnabled ?? false,
      volume: _musicVolumeDraft ?? game?.musicVolume ?? 35,
      homeVisible: _musicHomeVisible,
      minigameActive: _dish.active || _job.active,
    );
    if (!force && config == _lastMusicConfig) return;
    _lastMusicConfig = config;
    unawaited(
      _music.configure(
        enabled: config.enabled,
        volume: config.volume,
        homeVisible: config.homeVisible,
        minigameActive: config.minigameActive,
      ),
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _hintTimer?.cancel();
    _needsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_music.dispose().catchError((Object _) {}));
    super.dispose();
  }

  void _showTaskFeedback(String text) {
    _feedbackTimer?.cancel();
    if (!mounted) return;
    setState(() => _taskFeedback = text);
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _taskFeedback = null);
    });
  }

  void _scheduleHintCollapse() {
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_nextStepCollapsed) {
        setState(() => _nextStepCollapsed = true);
      }
    });
  }

  void _toggleNextStep() {
    setState(() => _nextStepCollapsed = !_nextStepCollapsed);
    if (_nextStepCollapsed) {
      _hintTimer?.cancel();
    } else {
      _scheduleHintCollapse();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _configureMusic(force: true);
    if (state == AppLifecycleState.resumed && mounted) {
      if (!c.busy) unawaited(_resumeAndNotify());
      setState(() {});
    }
  }

  Future<void> _resumeAndNotify() async {
    await c.load();
    _showLoginBonus();
  }

  void _showLoginBonus() {
    if (mounted && c.loginBonusAwarded > 0) {
      message('За ежедневный вход: +${c.loginBonusAwarded} монет');
      c.loginBonusAwarded = 0;
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          margin: widget.useMeshyModels && tab == 0
              ? EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  MediaQuery.sizeOf(context).height *
                      (MediaQuery.sizeOf(context).width >
                              MediaQuery.sizeOf(context).height
                          ? .48
                          : .64),
                )
              : null,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<bool> act(
    String label,
    void Function(GameState) action, {
    String? success,
    String? id,
  }) async {
    try {
      final chapterBefore = currentChapter(s);
      await c.change(label, action, id: id);
      if (mounted && currentChapter(s) > chapterBefore) {
        setState(() {
          reaction++;
          petAction = PetAction.celebrate;
        });
      }
      if (success != null) message(success);
      return true;
    } on GameRule catch (e) {
      message(e.message);
      return false;
    } catch (_) {
      message(
        'Не удалось сохранить. Действие не подтверждено — попробуй ещё раз.',
      );
      return false;
    }
  }

  bool _missionIncomeEligible(Mission mission, DateTime now) =>
      (!isCanonicalLesson(mission.id) || mission.id == 'P01') &&
      s.incomeAvailable &&
      !s.rewardClaimed(mission, now);

  int get _completedLessonCount =>
      allMissions.where((mission) => s.completed.contains(mission.id)).length;

  HouseholdJob get _selectedJob =>
      householdJobs[_selectedJobId] ?? householdJobForPeriod(s.day);

  void _showInRoom(String action) {
    setState(() {
      _catalogCareIntent = action;
      tab = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushSceneGuidance());
  }

  Future<void> _goToRoom(HomeRoom destination) async {
    if (c.busy || s.currentRoom == destination.assetName) return;
    await act(
      'Переход: ${destination.label}',
      (state) => state.setCurrentRoom(destination.assetName),
    );
  }

  void _flushSceneGuidance() {
    if (!mounted || !_sceneReady || tab != 0 || _catalogCareIntent == null) {
      return;
    }
    final scene = _sceneKey.currentState;
    if (scene == null) return;
    final action = _catalogCareIntent!;
    _catalogCareIntent = null;
    scene.showAction(action);
  }

  Future<void> _showJobPicker() async {
    final job = await showModalBottomSheet<HouseholdJob>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => HouseholdJobPicker(
        currentRoom: s.currentRoom,
        incomeAvailable: s.incomeAvailable,
        planConfirmed: s.planConfirmed,
        onSelected: (selection) => Navigator.of(sheetContext).pop(selection),
      ),
    );
    if (!mounted || job == null) return;
    setState(() => _selectedJobId = job.id);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!s.planConfirmed) {
      setState(() => tab = 1);
      message(
        'Сначала составь план дня. План не переводит монеты, а после него можно выполнить любое поручение.',
      );
      return;
    }
    if (s.currentRoom != job.room) {
      await _sceneKey.currentState?.requestAction('room', targetRoom: job.room);
      message(
        'Переходим в ${HomeRoom.values.firstWhere((room) => room.assetName == job.room).label.toLowerCase()}. Там снова открой «Дела» и нажми «Начать».',
      );
      return;
    }
    setState(() => _taskFeedback = null);
    await _sceneKey.currentState?.requestAction('job_${job.id.toLowerCase()}');
  }

  void mission(Mission m) {
    if (!s.planConfirmed && !{'B02', 'S01'}.contains(m.id)) {
      setState(() => tab = 1);
      message(
        'Сначала составим план. План помогает решить, на что потратить деньги, '
        'но не переводит монеты. Потом получим доход от родителей за помощь.',
      );
      return;
    }
    if (isCanonicalLesson(m.id)) {
      Navigator.of(context)
          .push<String>(
            MaterialPageRoute(
              builder: (lessonContext) => CanonLessonPage(
                lessonId: m.id,
                state: s,
                onSubmit: (submission) async {
                  late CanonLessonReceipt receipt;
                  await c.change('Задание: ${m.title}', (state) {
                    final before = CanonLessonSnapshot(state);
                    final alreadyCompleted = state.completed.contains(
                      canonLessonMarker(
                        submission.lessonId,
                        submission.snapshotDay,
                      ),
                    );
                    final reward = submission.apply(state);
                    if (!alreadyCompleted &&
                        !submission.practice &&
                        submission.lessonId == 'P06' &&
                        state.owned.contains(state.goalId)) {
                      state.completed.add('canon:goal-achieved:${state.day}');
                    }
                    receipt = CanonLessonReceipt(
                      submission: submission,
                      reward: reward,
                      applied: !alreadyCompleted && !submission.practice,
                      before: before,
                      after: state,
                    );
                  });
                  return receipt;
                },
                onGo: (route) => Navigator.pop(lessonContext, route),
              ),
            ),
          )
          .then((route) {
            if (mounted && route != null) {
              followStory(firstDayGuide(s)?.target ?? route);
            }
          });
      return;
    }
    final practice = s.rewardClaimed(m, DateTime.now());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MissionPage(
          mission: m,
          practice: practice,
          incomeAvailable: s.incomeAvailable,
          onComplete: (choice, independent) async {
            var reward = 0;
            final now = DateTime.now();
            await c.change('Задание: ${m.title}', (state) {
              reward = state.finish(m, choice, now, withoutHint: independent);
            });
            return reward;
          },
        ),
      ),
    );
  }

  void followStory(String target) {
    if (target == 'S01' && firstDayGuide(s)?.target == 'S01') {
      dreams();
      return;
    }
    final lessons = allMissions.where((mission) => mission.id == target);
    if (lessons.isNotEmpty) {
      mission(lessons.first);
    } else if (target.startsWith('job:')) {
      final job = householdJobs[target.substring(4)];
      if (job == null) return;
      setState(() => _selectedJobId = job.id);
      _showInRoom('job_${job.id.toLowerCase()}');
    } else if (target.startsWith('room:')) {
      final destination = HomeRoom.values.where(
        (room) => room.assetName == target.substring(5),
      );
      if (destination.isNotEmpty) _goToRoom(destination.first);
    } else if (target.startsWith('intro:')) {
      _openIntroExplanation(target);
    } else if (target == 'care' || target == 'play') {
      _showInRoom(
        target == 'play'
            ? 'play'
            : !s.cared.contains(0)
            ? 'feed'
            : !s.cared.contains(2)
            ? 'clean'
            : 'play',
      );
    } else if (target == 'catalog') {
      _openCatalog();
    } else if (target == 'defer:ball') {
      act(
        'Отложить покупку мяча',
        (state) {
          state.completed.add('canon:ball-deferred:${state.day}');
        },
        success: 'Мяч можно купить позже. Монеты сохранились.',
      );
    } else if (target == 'defer:dream') {
      act(
        'Продолжить копить на мечту',
        (state) {
          state.completed.add('canon:goal-deferred:${state.day}');
        },
        success: 'Продолжим копить. Все отложенные монеты сохранились.',
      );
    } else if (target == 'dreams') {
      dreams();
    } else if (target == 'day') {
      nextDay();
    } else if (target == 'album') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => AlbumPage(state: s)));
    } else {
      setState(() {
        tab = target == 'budget' ? 1 : 0;
        reaction = 0;
      });
    }
  }

  Future<void> _openIntroExplanation(String target) async {
    final explanation = firstDayGuideExplanation(s, target);
    if (explanation == null) return;
    final understood = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (pageContext) => Scaffold(
          backgroundColor: cream,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Heading(
                      target == 'intro:money'
                          ? 'Монетки на каждый день'
                          : 'Наша большая мечта',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      explanation,
                      style: const TextStyle(fontSize: 18, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(pageContext, true),
                      child: const Text('Понятно!'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || understood != true) return;
    try {
      await c.acknowledgeIntro(target.substring(6));
    } on GameRule catch (error) {
      message(error.message);
    } catch (_) {
      message('Не удалось сохранить шаг. Попробуй ещё раз.');
    }
  }

  Future<void> _openCatalog() async {
    setState(() => tab = 1);
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (catalogContext) => CatalogPage(
          controller: c,
          onAction: act,
          useMeshyModels: widget.useMeshyModels,
          onSceneCare: widget.useMeshyModels ? _showInRoom : null,
          onOpenBudget: () => Navigator.pop(catalogContext),
        ),
      ),
    );
    if (mounted && action != null) _showInRoom(action);
  }

  void celebrateAtHome() {
    setState(() {
      tab = 0;
      reaction = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          reaction++;
          petAction = PetAction.celebrate;
        });
      }
    });
  }

  Future<void> care(int index) async {
    final price = s.careCost(index);
    final ok = await act(
      ['Кормление', 'Игра', 'Купание'][index],
      (state) => state.care(index),
      success: [
        price == 0
            ? 'Повтор кормления · бесплатно.'
            : 'Вкусно! Сытость выросла. −10 монет',
        'Здорово поиграли! Бесплатно.',
        price == 0 ? 'Повтор ухода · бесплатно.' : 'Чисто и уютно! −5 монет',
      ][index],
    );
    if (ok && mounted) {
      setState(() {
        reaction++;
        petAction = PetAction.values[index + 1];
      });
    }
  }

  Map<String, Object?> sceneState() => {
    'room': s.currentRoom,
    'species': ['kitten', 'puppy', 'hamster'][s.species],
    'color': 'fur_${(s.color % 3 + 1).toString().padLeft(2, '0')}',
    'wearable': s.equippedWearable,
    'stage': s.stage,
    'owned': s.owned.toList(),
    'purchased': s.purchased.toList(),
    'lampOn': s.currentLampOn,
    'starsOn': s.starsOn,
    'nightlightOn': s.nightlightOn,
    'reducedMotion':
        s.reducedMotion || MediaQuery.of(context).disableAnimations,
    'busy': c.busy,
    'jobsAllowed': s.planConfirmed,
    'jobPeriod': s.day,
    'selectedJobId': _selectedJob.id,
  };

  Future<SceneActionResult> sceneAction(SceneAction action) async {
    if (!action.isAllowedIn(s.currentRoom) || c.busy) {
      return SceneActionResult(false, state: sceneState());
    }
    final operationId = 'scene:${action.id}';
    if (action.action == 'complete_job') {
      final job = householdJobs[action.jobId];
      if (job == null ||
          _job.stage != 'awaiting_ack' ||
          _job.jobId != job.id ||
          _job.completed != job.totalSteps) {
        return SceneActionResult(
          false,
          message: 'Сначала закончим поручение.',
          state: sceneState(),
        );
      }
      var earned = 0;
      final quick =
          _jobStartedAt != null &&
          DateTime.now().difference(_jobStartedAt!) <=
              const Duration(seconds: 45);
      final ok = await act('Поручение: ${job.title}', (state) {
        earned = state.finishJob(
          job.id,
          period: action.jobPeriod!,
          completedQuickly: quick,
          petHappy: _jobStartedHappy,
        );
      }, id: operationId);
      if (ok && earned > 0) {
        await _sceneKey.currentState?.playCue('coinSave');
      }
      final text = ok
          ? earned > 0
                ? '${job.title}: готово! От родителей за помощь: +$earned. '
                      'Теперь в «Сейчас» ${s.wallet[0]} монет.'
                : '${job.title}: готово! Тренировка · без монет. '
                      'Доход этого дня уже получен.'
          : 'Не получилось сохранить результат. Попробуем ещё раз.';
      if (ok) message(text);
      if (ok) _showTaskFeedback(text);
      return SceneActionResult(ok, message: text, state: sceneState());
    }
    if (action.action == 'wash_dishes') {
      if (_dish.stage != 'awaiting_ack' || _dish.cleaned != 6) {
        return SceneActionResult(
          false,
          message: 'Сначала закончим поручение.',
          state: sceneState(),
        );
      }
      var earned = 0;
      final quick =
          _dishStartedAt != null &&
          DateTime.now().difference(_dishStartedAt!) <=
              const Duration(seconds: 45);
      final ok = await act('Поручение: чистая посуда', (state) {
        earned = state.finishDishJob(
          period: action.jobPeriod!,
          completedQuickly: quick,
          petHappy: _dishStartedHappy,
        );
      }, id: operationId);
      if (ok && earned > 0) {
        await _sceneKey.currentState?.playCue('coinSave');
      }
      final text = ok
          ? earned > 0
                ? 'Посуда чистая! От родителей за помощь: +$earned. '
                      'Теперь в «Сейчас» ${s.wallet[0]} монет. План можно уточнить, '
                      'но он не переводит монеты.'
                : 'Посуда чистая! Тренировка · без монет. '
                      'Доход этого дня уже получен.'
          : 'Не получилось сохранить результат. Попробуем ещё раз.';
      if (ok) message(text);
      if (ok) _showTaskFeedback(text);
      return SceneActionResult(ok, message: text, state: sceneState());
    }
    if (action.action == 'room' ||
        action.action == 'stars' ||
        action.action == 'nightlight') {
      final ok = await act(
        action.action == 'room' ? 'Переход в комнату' : 'Светильник',
        (state) {
          if (action.action == 'room') state.setCurrentRoom(action.targetRoom!);
          if (action.action == 'stars' || action.action == 'nightlight') {
            state.toggleOptionalFixture(action.action);
          }
        },
        id: operationId,
      );
      return SceneActionResult(ok, state: sceneState());
    }
    if (!s.planConfirmed && action.action != 'play') {
      setState(() => tab = 1);
      message('Сначала решим, сколько оставим на заботу и мечту.');
      return SceneActionResult(false, state: sceneState());
    }
    final index = switch (action.action) {
      'feed' => 0,
      'play' => 1,
      _ => 2,
    };
    final price = s.careCost(index);
    final description = switch (index) {
      0 => 'Покормить ${s.name}',
      1 => 'Поиграть с ${s.name}',
      _ when s.species == 2 => 'Почистить шёрстку в песочной ванночке',
      _ => 'Помыть лапы ${s.name}',
    };
    if (s.wallet[0] < price) {
      final text =
          'Не хватает ${price - s.wallet[0]} монет. '
          'Можно отложить заботу, проверить конверты и план или выполнить оплачиваемое поручение, '
          'если доход этого дня ещё не получен.';
      final openBudget = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Пока не хватает монет'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Вернуться к другу'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Открыть бюджет'),
            ),
          ],
        ),
      );
      if (mounted && openBudget == true) setState(() => tab = 1);
      return SceneActionResult(false, message: text, state: sceneState());
    }
    final effect =
        index == 1 && s.purchased.contains('ball') && s.needs[1] == 100
        ? 'Радость уже полная. Поиграем с новым мячом просто так.'
        : index != 1 && s.cared.contains(index)
        ? 'Показатель уже обновлён после сегодняшней заботы; повторим только действие.'
        : switch (index) {
            0 => 'Сытость станет ${(s.needs[0] + 25).clamp(0, 100)} из 100.',
            1 => 'Радость станет ${(s.needs[1] + 20).clamp(0, 100)} из 100.',
            _ => 'Чистота станет ${(s.needs[2] + 25).clamp(0, 100)} из 100.',
          };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$description?'),
        content: Text(
          '${index == 1 ? 'Бесплатная игра.' : 'Обязательная забота.'} $effect\n\n'
          '${price == 0
              ? index == 1
                    ? 'Игра бесплатна и не меняет конверты.'
                    : 'За эту заботу сегодня уже заплачено. Повтор бесплатный.'
              : 'Потратим $price монет. В конверте «Сейчас» останется ${s.wallet[0] - price}.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(price == 0 ? 'Да · бесплатно' : 'Да · $price монет'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return const SceneActionResult(false);
    }
    final ok = await act(
      ['Кормление', 'Игра', 'Чистота'][index],
      (state) {
        if (index == 1 && state.purchased.contains('ball')) {
          // The new ball may have filled joy to 100 at purchase. A replay is
          // still a visible, free game and never changes the wallet.
          if (state.needs[1] < 100) state.care(1);
          state.completed.add('intro-toy-play');
        } else {
          state.care(index);
        }
      },
      id: operationId,
      success: [
        'Вкусно! Сытость выросла.',
        'Здорово поиграли!',
        'Теперь чисто и уютно!',
      ][index],
    );
    return SceneActionResult(ok, state: sceneState());
  }

  Future<void> inspectProp() async {
    final selectedRoom = room;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cream,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        MeshyPropView.labels[selectedRoom.index],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть осмотр',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const CozyIcon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Поверни предмет пальцем'),
              ),
              Expanded(child: MeshyPropView(roomIndex: selectedRoom.index)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> dreams() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cream,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => Sheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Heading(
                'Маленькие мечты',
                subtitle: 'Накопления остаются с тобой при смене цели.',
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < goals.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Surface(
                    color: s.goalId == goals[i].id ? sage : Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CozyIcon(
                              [
                                Icons.cottage_rounded,
                                Icons.yard_rounded,
                                Icons.auto_awesome_rounded,
                              ][i],
                              size: firstDayGuide(s)?.target == 'S01' ? 64 : 34,
                              color: blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                goals[i].name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Coins(goals[i].price),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(goals[i].description),
                        if (widget.useMeshyModels)
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => ScenePreviewPage(
                                  state: s,
                                  goalId: goals[i].id,
                                  title: goals[i].name,
                                  description: goals[i].description,
                                  priceLabel: s.owned.contains(goals[i].id)
                                      ? 'Мечта уже сбылась'
                                      : '${goals[i].price} монет из «Мечта»',
                                ),
                              ),
                            ),
                            icon: const CozyIcon(Icons.visibility_rounded),
                            label: const Text('Посмотреть в комнате'),
                          ),
                        const SizedBox(height: 12),
                        if (firstDayGuide(s)?.target == 'S01')
                          FilledButton(
                            key: ValueKey('intro-goal-${goals[i].id}'),
                            onPressed: c.busy
                                ? null
                                : () async {
                                    final selected = goals[i];
                                    final submission =
                                        CanonLessonSubmission.capture(
                                          s,
                                          lessonId: 'S01',
                                          practice: false,
                                          goalId: selected.id,
                                        );
                                    final ok = await act(
                                      'Первая мечта: ${selected.name}',
                                      (state) => submission.apply(state),
                                      id: 'intro:choose-goal:${s.day}',
                                      success:
                                          'Вот наша цель: ${selected.name}!',
                                    );
                                    if (ok && context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                            child: const Text('Это моя цель'),
                          )
                        else if (s.owned.contains(goals[i].id))
                          const Text(
                            'Уже украшает вашу комнату',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          )
                        else if (s.goalId == goals[i].id)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${s.wallet[1]} из ${goals[i].price} монет накоплено',
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed:
                                    c.busy || s.wallet[1] < goals[i].price
                                    ? null
                                    : () async {
                                        if (widget.useMeshyModels) {
                                          final confirmed =
                                              await Navigator.of(
                                                context,
                                              ).push<bool>(
                                                MaterialPageRoute(
                                                  builder: (_) => ScenePreviewPage(
                                                    state: s,
                                                    goalId: goals[i].id,
                                                    title: goals[i].name,
                                                    description:
                                                        goals[i].description,
                                                    priceLabel:
                                                        '${goals[i].price} монет из «Мечта» · останется ${s.wallet[1] - goals[i].price}',
                                                    confirmLabel:
                                                        'Исполнить мечту',
                                                    canConfirm:
                                                        !c.busy &&
                                                        s.wallet[1] >=
                                                            goals[i].price,
                                                  ),
                                                ),
                                              );
                                          if (confirmed != true ||
                                              !context.mounted) {
                                            return;
                                          }
                                        }
                                        final ok = await act(
                                          'Мечта: ${goals[i].name}',
                                          (state) {
                                            state.buyGoal();
                                            if (state.completed.contains(
                                              'P06',
                                            )) {
                                              state.completed.add(
                                                'canon:goal-achieved:${state.day}',
                                              );
                                            }
                                          },
                                          id: 'buy:${goals[i].id}',
                                          success:
                                              'Мечта сбылась! Предмет появился в комнате.',
                                        );
                                        if (ok && context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                child: Text(
                                  s.wallet[1] < goals[i].price
                                      ? 'Ещё ${goals[i].price - s.wallet[1]} монет'
                                      : 'Исполнить мечту',
                                ),
                              ),
                            ],
                          )
                        else
                          OutlinedButton(
                            onPressed: c.busy
                                ? null
                                : () => act(
                                    'Новая цель: ${goals[i].name}',
                                    (state) => state.goalId = goals[i].id,
                                  ),
                            child: const Text('Выбрать эту мечту'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cream,
      builder: (context) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => AnimatedBuilder(
          animation: c,
          builder: (context, _) => Sheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Heading(
                  'Растём вместе',
                  subtitle: 'Маленькие шаги становятся большими привычками.',
                ),
                const SizedBox(height: 20),
                Surface(
                  color: sage,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.stageName} · ${s.stage}/3',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Разных ситуаций: $_completedLessonCount из ${allMissions.length}',
                      ),
                      Text('Полных дней заботы: ${s.careDays}'),
                      Text('Подтверждённых планов: ${s.plansConfirmed}'),
                      Text('Зачтённых дней для роста: ${s.qualifyingPeriods}'),
                      Text('Исполнено желаний: ${s.owned.length}'),
                      const SizedBox(height: 12),
                      const Text(
                        'Друг растёт после 3 и 5 зачтённых дней. В каждом нужны забота, положительный вклад в накопления и сравнение плана с фактом. Если результат отличается от плана, выбираем объяснение. Достигнутая стадия сохраняется.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Меньше движения'),
                  subtitle: const Text(
                    'Спокойные переходы и действия без прыжков',
                  ),
                  value: s.reducedMotion,
                  onChanged: c.busy
                      ? null
                      : (v) => act(
                          'Настройка движения',
                          (state) => state.reducedMotion = v,
                        ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Озвучка реплик'),
                  subtitle: const Text('Голос питомца в диалогах'),
                  value: s.voiceEnabled,
                  onChanged: c.busy
                      ? null
                      : (v) => act(
                          'Настройка озвучки',
                          (state) => state.voiceEnabled = v,
                        ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Фоновая музыка'),
                  subtitle: const Text('Тихая мелодия дома'),
                  value: s.musicEnabled,
                  onChanged: c.busy
                      ? null
                      : (v) => act(
                          'Настройка музыки',
                          (state) => state.musicEnabled = v,
                        ),
                ),
                FutureBuilder<bool>(
                  future: _musicAvailable,
                  builder: (context, snapshot) => snapshot.data == false
                      ? const Text(
                          'Музыка пока не установлена. Игра работает без неё.',
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  'Громкость музыки: ${_musicVolumeDraft ?? s.musicVolume}%',
                ),
                Slider(
                  value: (_musicVolumeDraft ?? s.musicVolume).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_musicVolumeDraft ?? s.musicVolume}%',
                  semanticFormatterCallback: (value) =>
                      '${value.round()} процентов',
                  onChanged: c.busy
                      ? null
                      : (value) {
                          setState(() => _musicVolumeDraft = value.round());
                          refreshSheet(() {});
                        },
                  onChangeEnd: c.busy
                      ? null
                      : (value) async {
                          final volume = value.round();
                          await act(
                            'Настройка громкости музыки',
                            (state) => state.musicVolume = volume,
                          );
                          if (mounted) setState(() => _musicVolumeDraft = null);
                          if (sheetContext.mounted) refreshSheet(() {});
                        },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Звуки действий'),
                  subtitle: const Text('Короткие звуки кнопок и домашних дел'),
                  value: s.soundEnabled,
                  onChanged: c.busy
                      ? null
                      : (v) => act(
                          'Настройка звука',
                          (state) => state.soundEnabled = v,
                        ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Громкость звуков: ${_soundVolumeDraft ?? s.soundVolume}%',
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: (_soundVolumeDraft ?? s.soundVolume).toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_soundVolumeDraft ?? s.soundVolume}%',
                  semanticFormatterCallback: (value) =>
                      '${value.round()} процентов',
                  onChanged: c.busy
                      ? null
                      : (value) {
                          setState(() => _soundVolumeDraft = value.round());
                          refreshSheet(() {});
                        },
                  onChangeEnd: c.busy
                      ? null
                      : (value) async {
                          final volume = value.round();
                          await act(
                            'Настройка громкости',
                            (state) => state.soundVolume = volume,
                          );
                          if (mounted) setState(() => _soundVolumeDraft = null);
                          if (sheetContext.mounted) refreshSheet(() {});
                        },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(s.graphicsQuality),
                  initialValue: s.graphicsQuality,
                  decoration: const InputDecoration(
                    labelText: 'Качество графики',
                    helperText: 'Авто подстраивается под телефон',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Авто')),
                    DropdownMenuItem(value: 'low', child: Text('Низкое')),
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('Стандартное'),
                    ),
                    DropdownMenuItem(value: 'high', child: Text('Высокое')),
                  ],
                  onChanged: c.busy
                      ? null
                      : (value) {
                          if (value == null || value == s.graphicsQuality) {
                            return;
                          }
                          act(
                            'Настройка графики',
                            (state) => state.graphicsQuality = value,
                          );
                        },
                ),
                const Divider(),
                const Text(
                  'Копилыч · студия 37',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Дом и игровые данные доступны без интернета. Монеты только игровые. Нет реальных платежей, рекламы и регистрации. Имя питомца и прогресс хранятся на этом устройстве.',
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Копилыч',
                    applicationVersion: '0.5.2',
                  ),
                  child: const Text('Лицензии компонентов'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _soundVolumeDraft = null;
        _musicVolumeDraft = null;
      });
    }
  }

  Future<void> nextDay() async {
    if (c.busy) return;
    if (!s.planConfirmed) {
      message(
        'Сначала составь план этого дня. При пустом кошельке можно сохранить план 0 / 0 / 0.',
      );
      return;
    }
    final summary = s.currentPeriodSummary;
    final snapshot = jsonEncode(summary.toJson());
    final stageBefore = s.stage;
    final decision = await showModalBottomSheet<PeriodReviewDecision>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cream,
      builder: (context) => PeriodReviewSheet(
        summary: summary,
        qualifyingPeriods: s.qualifyingPeriods,
      ),
    );
    if (!mounted || decision == null) return;
    final saved = await act('Новый игровой день', (state) {
      if (jsonEncode(state.currentPeriodSummary.toJson()) != snapshot) {
        throw const GameRule(
          'Итоги изменились. Открой их ещё раз перед завершением дня.',
        );
      }
      state.endDay(reviewed: true, explanation: decision.explanation);
    });
    if (saved && mounted) {
      message(
        s.stage > stageBefore
            ? 'Друг вырос: забота, накопления и сравнение плана помогли вам пройти ${s.qualifyingPeriods} дней вместе!'
            : 'Доброе утро! Итоги сохранены. В новом дне можно снова заработать до 30 монет.',
      );
    }
  }

  void gameMenu() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: cream,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Наш дом',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            for (final entry in [
              (1, 'Бюджет', Icons.account_balance_wallet_rounded),
              (2, 'Задания', Icons.auto_stories_rounded),
              (3, 'История', Icons.route_rounded),
            ])
              ListTile(
                leading: CozyIcon(entry.$3),
                title: Text(entry.$2),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => tab = entry.$1);
                },
              ),
            ListTile(
              leading: const CozyIcon(Icons.flag_rounded),
              title: const Text('Выбрать цель'),
              onTap: () {
                Navigator.pop(sheetContext);
                dreams();
              },
            ),
            ListTile(
              leading: const CozyIcon(Icons.nights_stay_rounded),
              title: const Text('Итоги дня'),
              onTap: () {
                Navigator.pop(sheetContext);
                nextDay();
              },
            ),
            ListTile(
              leading: const CozyIcon(Icons.lightbulb_outline_rounded),
              title: const Text('Как играть'),
              onTap: () {
                Navigator.pop(sheetContext);
                showFinanceIntro(context);
              },
            ),
            ListTile(
              leading: const CozyIcon(Icons.menu_book_rounded),
              title: const Text('Словарик'),
              onTap: () {
                Navigator.pop(sheetContext);
                showFinanceGlossary(context);
              },
            ),
            ListTile(
              leading: const CozyIcon(Icons.tune_rounded),
              title: const Text('Настройки'),
              onTap: () {
                Navigator.pop(sheetContext);
                settings();
              },
            ),
            ListTile(
              leading: const CozyIcon(Icons.family_restroom_rounded),
              title: const Text('Раздел взрослого'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdultGate(controller: c),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget gameSurface() => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(offstage: tab != 0, child: homePage()),
      if (tab != 0)
        ColoredBox(
          color: cream,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('back-to-home'),
                        onPressed: () => setState(() => tab = 0),
                        icon: const CozyIcon(Icons.arrow_back_rounded),
                        label: const Text('Дом'),
                      ),
                      const Spacer(),
                      Text(
                        ['Дом', 'Бюджет', 'Задания', 'История'][tab],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: currentPage()),
              ],
            ),
          ),
        ),
      if (c.busy)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      _scheduleMusicSync(ModalRoute.of(context)?.isCurrent ?? false);
      if (c.loadError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Не удалось прочитать прогресс. Сохранение оставлено без изменений.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: c.load,
                    child: const Text('Попробовать снова'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (c.state == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (s.name == null) {
        if (widget.useMeshyModels) {
          return AdoptionPage(
            busy: c.busy,
            onStart: (species, color, accessory, name) => act(
              'Первый друг',
              (state) {
                state.species = species;
                state.color = color;
                state.accessory = 0;
                state.name = name.trim().isEmpty
                    ? defaultNames[species]
                    : name.trim();
                state.markAdopted(DateTime.now());
                state.completed.add('intro-started');
              },
              success: 'Заботься о питомце: поиграй с ним в гостиной.',
            ),
          );
        }
        return Onboarding(
          busy: c.busy,
          useMeshyModels: widget.useMeshyModels,
          onStart: (species, color, accessory, name) => act(
            'Первый друг',
            (state) {
              state.species = species;
              state.color = color;
              state.accessory = accessory;
              state.name = name.trim().isEmpty
                  ? defaultNames[species]
                  : name.trim();
              state.markAdopted(DateTime.now());
              state.completed.add('intro-started');
            },
            success: 'Заботься о питомце: поиграй с ним в гостиной.',
          ),
        );
      }
      if (widget.useMeshyModels) {
        return Scaffold(body: gameSurface());
      }
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 16, 0),
                    child: Row(
                      children: [
                        const CozyIcon(
                          Icons.pets_rounded,
                          color: blue,
                          size: 23,
                        ),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'копилыч',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _dish.active || _job.active
                              ? null
                              : settings,
                          tooltip: 'Рост и настройки',
                          icon: const CozyIcon(Icons.tune_rounded),
                        ),
                        IconButton(
                          onPressed: _dish.active || _job.active
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdultGate(controller: c),
                                  ),
                                ),
                          tooltip: 'Раздел взрослого',
                          icon: const CozyIcon(Icons.family_restroom_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: widget.useMeshyModels
                        ? Stack(
                            children: [
                              Offstage(offstage: tab != 0, child: homePage()),
                              if (tab != 0) currentPage(),
                            ],
                          )
                        : currentPage(),
                  ),
                  if (c.busy) const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          backgroundColor: cream,
          elevation: 0,
          indicatorColor: const Color(0xFFDFE8F5),
          onDestinationSelected: (v) async {
            if (_dish.stage == 'awaiting_ack') return;
            if (_job.stage == 'awaiting_ack') return;
            if (_dish.active) await _sceneKey.currentState?.cancelDishGame();
            if (_job.active) await _sceneKey.currentState?.cancelJobGame();
            if (mounted) {
              setState(() {
                tab = v;
                reaction = 0;
              });
            }
          },
          destinations: const [
            NavigationDestination(
              icon: CozyIcon(Icons.cottage_outlined),
              selectedIcon: CozyIcon(Icons.cottage_rounded),
              label: 'Дом',
            ),
            NavigationDestination(
              icon: CozyIcon(Icons.account_balance_wallet_outlined),
              selectedIcon: CozyIcon(Icons.account_balance_wallet_rounded),
              label: 'Бюджет',
            ),
            NavigationDestination(
              icon: CozyIcon(Icons.auto_stories_outlined),
              selectedIcon: CozyIcon(Icons.auto_stories_rounded),
              label: 'Задания',
            ),
            NavigationDestination(
              icon: CozyIcon(Icons.route_outlined),
              selectedIcon: CozyIcon(Icons.route_rounded),
              label: 'История',
            ),
          ],
        ),
      );
    },
  );

  Widget currentPage() => switch (tab) {
    1 => BudgetPage(
      controller: c,
      onAction: act,
      onDreams: dreams,
      useMeshyModels: widget.useMeshyModels,
      onSceneCare: widget.useMeshyModels ? _showInRoom : null,
    ),
    2 => missionsPage(),
    3 => StoryPage(state: s, onGo: followStory, onCelebrate: celebrateAtHome),
    _ => homePage(),
  };

  Widget homePage() {
    final now = DateTime.now();
    final currentJob = _selectedJob;
    final firstDayTask = firstDayGuide(s);
    final activeTask = firstDayTask ?? storyActiveTask(s);
    final next = allMissions.firstWhere(
      (m) => m.id == activeTask?.target,
      orElse: () => canonicalMissions.firstWhere((m) => m.id == 'P01'),
    );
    final lessonWithoutReward =
        isCanonicalLesson(next.id) &&
        next.id != 'P01' &&
        !s.completed.contains(canonLessonMarker(next.id, s.day));
    if (widget.useMeshyModels) {
      if (!_firstHomeFallbackShown &&
          firstDayTask == null &&
          s.day == 1 &&
          !s.cared.contains(s.day)) {
        _firstHomeFallbackShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && tab == 0 && !_dish.active && !_job.active) {
            _showTaskFeedback(
              'Что делаем сейчас: поиграй с питомцем в гостиной.',
            );
          }
        });
      }
      final currentRoom = HomeRoom.values.firstWhere(
        (r) => r.assetName == s.currentRoom,
      );
      // Подсказка ласки — только когда у истории нет активного задания
      // (не перехватывать канонические уроки S01→B02→P01 первого дня).
      final firstMinute = activeTask == null && !s.cared.contains(s.day);
      final stepTitle = firstMinute
          ? 'Гостиная · Погладить'
          : activeTask?.label;
      // Новый шаг — подсказка снова разворачивается.
      if (stepTitle != _nextStepKey) {
        _nextStepKey = stepTitle;
        _nextStepCollapsed = false;
        if (stepTitle != null) _scheduleHintCollapse();
      }
      return GameHome(
        state: s,
        ready: _sceneReady,
        busy: c.busy,
        dish: _dish,
        job: _job,
        jobId: currentJob.id,
        jobTitle: currentJob.title,
        jobRoom: currentJob.room,
        jobIncomeAvailable: s.incomeAvailable,
        taskFeedback: _taskFeedback,
        onDismissFeedback: () {
          _feedbackTimer?.cancel();
          setState(() => _taskFeedback = null);
        },
        onMenu: gameMenu,
        nextStepTitle: stepTitle,
        nextStepCollapsed: _nextStepCollapsed,
        onToggleNextStep: _toggleNextStep,
        onNextStep: firstMinute
            ? () => _sceneKey.currentState?.requestAction('play')
            : activeTask == null
            ? null
            : () => followStory(activeTask.target),
        onShowJob: () => _sceneKey.currentState?.showAction(
          'job_${currentJob.id.toLowerCase()}',
        ),
        lessonIncomeAvailable: _missionIncomeEligible(next, now),
        lessonWithoutReward: lessonWithoutReward,
        onViewportInsets: (top, right, bottom, left) => _sceneKey.currentState
            ?.updateViewportInsets(top, right, bottom, left),
        onJob: _showJobPicker,
        onDishStep: (step) => _sceneKey.currentState?.dishStep(step),
        onCancelDish: () async {
          await _sceneKey.currentState?.cancelDishGame();
          if (mounted) {
            _showTaskFeedback(
              'Поручение остановлено. Прогресс этого подхода не сохранён.',
            );
          }
        },
        onJobStep: (step) => _sceneKey.currentState?.jobStep(step),
        onJobPlacement: (source, target) =>
            _sceneKey.currentState?.placeJobItem(source, target),
        onCancelJob: () async {
          await _sceneKey.currentState?.cancelJobGame();
          if (mounted) {
            _showTaskFeedback(
              'Поручение остановлено. Прогресс этого подхода не сохранён.',
            );
          }
        },
        scene: SharedRoom(
          key: _sceneKey,
          sceneState: sceneState(),
          soundEnabled: s.soundEnabled,
          soundVolume: _soundVolumeDraft ?? s.soundVolume,
          graphicsQuality: s.graphicsQuality,
          paused: tab != 0,
          onReadyChanged: (ready) {
            if (mounted && _sceneReady != ready) {
              setState(() => _sceneReady = ready);
            }
            if (ready && _catalogCareIntent != null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _flushSceneGuidance(),
              );
            }
          },
          onAction: sceneAction,
          onDishChanged: (progress) {
            if (!mounted) return;
            if (_dish.stage == 'idle' && progress.stage != 'idle') {
              _dishStartedAt = DateTime.now();
              _dishStartedHappy = s.needs.every((need) => need > 70);
            } else if (progress.stage == 'idle') {
              _dishStartedAt = null;
              _dishStartedHappy = false;
            }
            setState(() => _dish = progress);
          },
          onJobChanged: (progress) {
            if (!mounted) return;
            if (_job.stage == 'idle' && progress.stage != 'idle') {
              _jobStartedAt = DateTime.now();
              _jobStartedHappy = s.needs.every((need) => need > 70);
            } else if (progress.stage == 'idle') {
              _jobStartedAt = null;
              _jobStartedHappy = false;
            }
            setState(() => _job = progress);
          },
        ),
        onRoom: _goToRoom,
        onCare: () =>
            _sceneKey.currentState?.requestAction(switch (currentRoom) {
              HomeRoom.kitchen => 'feed',
              HomeRoom.bathroom => 'clean',
              _ => 'play',
            }),
        onWater: null,
        onLamp: () => _sceneKey.currentState?.requestAction('lamp'),
        onPlan: () => setState(() => tab = 1),
        onMission: () => mission(next),
        onDream: dreams,
        onNextDay: nextDay,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Хорошо быть вместе',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${s.name} · день ${s.day}',
                    style: const TextStyle(color: muted, fontSize: 16),
                  ),
                  if (s.demoMode) ...[
                    const SizedBox(height: 6),
                    const Tag('ДЕМОРЕЖИМ', icon: Icons.smart_display_outlined),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: const Color(0xFFF5EACC),
              child: Coins(s.wallet[0]),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Semantics(
          label:
              '${speciesNames[s.species]} ${s.name}, ${s.stageName}. ${room.label}.',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: RoomStage(
              room: room,
              busy: c.busy,
              reducedMotion: s.reducedMotion,
              onCare: () => care(room.careIndex),
              onInspect: widget.useMeshyModels ? inspectProp : null,
              pet: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.useMeshyModels)
                    MeshyPetView(
                      species: s.species,
                      wearable: s.equippedWearable,
                      animation: PetAnimation.fromAction(petAction),
                      animationEvent: reaction,
                      reducedMotion: s.reducedMotion,
                    ),
                  PetScene(
                    species: s.species,
                    color: s.color,
                    accessory: s.visibleAccessory,
                    room: false,
                    transparent: true,
                    effectsOnly: widget.useMeshyModels,
                    showDecor: room == HomeRoom.living,
                    owned: s.owned,
                    purchased: s.purchased,
                    reducedMotion: s.reducedMotion,
                    reaction: reaction,
                    action: petAction,
                    stage: s.stage,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final nextRoom in HomeRoom.values)
              ChoiceChip(
                label: Text(nextRoom.label),
                selected: room == nextRoom,
                onSelected: (_) => setState(() => room = nextRoom),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            reaction > 0
                ? '«${actionLabels[petAction.index]}»'
                : '«Чем займёмся сегодня?»',
            style: const TextStyle(
              color: muted,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 12 : 0),
                  child: NeedMeter(
                    label: ['Сытость', 'Радость', 'Чистота'][i],
                    value: s.needs[i],
                    color: [
                      const Color(0xFFDFA467),
                      const Color(0xFF8BA77F),
                      const Color(0xFF7CA3BF),
                    ][i],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                  child: CareButton(
                    index: i,
                    busy: c.busy,
                    onTap: () => care(i),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => setState(() {
            tab = 3;
            reaction = 0;
          }),
          borderRadius: BorderRadius.circular(22),
          child: Surface(
            color: const Color(0xFFF9EDD8),
            child: Row(
              children: [
                const CozyIcon(Icons.auto_stories_rounded, color: blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ДОМ МАЛЕНЬКИХ МЕЧТ',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        currentChapter(s) == 6
                            ? 'История пройдена. Впереди новые мечты!'
                            : 'Глава ${currentChapter(s) + 1}: ${storyChapters(s)[currentChapter(s)].title}',
                      ),
                    ],
                  ),
                ),
                const CozyIcon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Surface(
          color: const Color(0xFFE5EDF8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Tag('МИНУТКА ОТКРЫТИЙ', icon: Icons.auto_awesome_rounded),
              const SizedBox(height: 9),
              Text(next.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              const Text('Реши маленькую задачку — помоги большой мечте.'),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => mission(next),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text('Попробовать'),
                    Text(
                      _missionIncomeEligible(next, now)
                          ? 'Награда: 30 монет'
                          : lessonWithoutReward
                          ? 'Без награды'
                          : 'Тренировка · без монет',
                    ),
                    const CozyIcon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: dreams,
          borderRadius: BorderRadius.circular(22),
          child: Surface(
            color: sage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CozyIcon(Icons.flag_rounded, color: blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.goal.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const CozyIcon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.owned.contains(s.goalId)
                      ? 'Мечта исполнена! Выбери новую.'
                      : '${s.wallet[1]} из ${s.goal.price} монет',
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: (s.wallet[1] / s.goal.price).clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: Colors.white,
                    color: const Color(0xFF749273),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  reaction++;
                  petAction = PetAction.love;
                });
                message(
                  '${s.name} рад твоему вниманию. Общение всегда бесплатно.',
                );
              },
              icon: const CozyIcon(Icons.favorite_border_rounded),
              label: const Text('Обнять · бесплатно'),
            ),
            TextButton(
              onPressed: c.busy ? null : nextDay,
              child: const Text('Завершить день'),
            ),
          ],
        ),
      ],
    );
  }

  Widget missionsPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Heading(
        'Учимся на маленьком',
        subtitle: 'Чтобы уверенно мечтать о большом.',
      ),
      const SizedBox(height: 20),
      Surface(
        color: sage,
        child: Row(
          children: [
            const CozyIcon(Icons.explore_rounded, size: 36, color: blue),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '$_completedLessonCount из ${allMissions.length} открытий\nУ каждого решения есть результат.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'За одно поручение или учебное задание в игровом дне родители дают '
        '30 монет за помощь. Деньги в условиях задач учебные. После выплаты '
        'остальные задания — тренировка без монет.',
      ),
      const SizedBox(height: 18),
      for (final group in ['once', 'daily', 'weekly']) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            {
              'once': 'Первое знакомство',
              'daily': 'На каждый игровой день',
              'weekly': 'Мастерская решений',
            }[group]!,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final m in allMissions.where((m) => m.period == group))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => mission(m),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: s.completed.contains(m.id)
                            ? sage
                            : peach,
                        child: CozyIcon(
                          s.completed.contains(m.id)
                              ? Icons.check_rounded
                              : Icons.lightbulb_outline_rounded,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${topicNames[['budget', 'savings', 'shopping'].indexOf(m.topic)]} · '
                              '${m.kind == 'action' ? 'действие' : m.skill} · '
                              '${_missionIncomeEligible(m, DateTime.now())
                                  ? 'Награда: 30 монет'
                                  : isCanonicalLesson(m.id) && m.id != 'P01' && !s.completed.contains(canonLessonMarker(m.id, s.day))
                                  ? 'Без награды'
                                  : 'Тренировка · без монет'}',
                              style: const TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                      const CozyIcon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
      const SizedBox(height: 12),
      const Text(
        'За поручения и оплачиваемые задания можно получить всего 30 монет за игровой день. Новый день начинается после итогов; ждать календаря не нужно. Повторы помогают тренироваться.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 22),
      const Tag('СПРАВОЧНИК', icon: Icons.menu_book_rounded),
      const SizedBox(height: 10),
      for (final term in glossary)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Surface(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(term.term, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(term.definition, style: const TextStyle(color: muted)),
              ],
            ),
          ),
        ),
    ],
  );
}
