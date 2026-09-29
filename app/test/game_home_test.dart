import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/scene_bridge.dart';
import 'package:kopilych/ui.dart';

class _SceneProbe extends StatefulWidget {
  const _SceneProbe({required this.onCreate});
  final VoidCallback onCreate;

  @override
  State<_SceneProbe> createState() => _SceneProbeState();
}

class _SceneProbeState extends State<_SceneProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('rotation-scene'), color: Colors.white);
}

void main() {
  testWidgets(
    'generic job HUD routes steps and locks saving on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = GameState()
        ..name = 'Бублик'
        ..currentRoom = 'kitchen';
      state.confirmPlan([15, 5, 20]);
      final steps = <String>[];
      var menus = 0, cancelled = 0, jobs = 0;
      Future<void> show([JobProgress job = const JobProgress()]) =>
          tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              home: Scaffold(
                body: GameHome(
                  state: state,
                  scene: const ColoredBox(color: Colors.white),
                  ready: true,
                  busy: false,
                  job: job,
                  jobId: 'J06',
                  jobTitle: 'Подмети пол',
                  jobRoom: 'living',
                  onRoom: (_) {},
                  onCare: () {},
                  onLamp: () {},
                  onPlan: () {},
                  onMission: () {},
                  onDream: () {},
                  onNextDay: () {},
                  onJob: () => jobs++,
                  onShowJob: () {},
                  onMenu: () => menus++,
                  onJobStep: steps.add,
                  onCancelJob: () => cancelled++,
                ),
              ),
            ),
          );
      await show();
      expect(find.text('Гостиная · Подмети пол'), findsOneWidget);
      expect(find.byKey(const ValueKey('scene-water')), findsNothing);
      expect(state.wallet[0], 100);
      await tester.tap(find.byKey(const ValueKey('scene-job')));
      expect(jobs, 1);
      expect(tester.takeException(), isNull);
      state.currentRoom = 'living';
      await show(
        const JobProgress(
          jobId: 'J06',
          title: 'Подмети пол',
          room: 'living',
          stage: 'active',
          completed: 1,
          total: 6,
          nextStep: 'sweep',
          feedbackCode: 'wrong_target',
          feedbackMessage: 'Сначала собери мусор в совок.',
        ),
      );
      expect(find.text('Собери мусор веником в совок.'), findsOneWidget);
      expect(find.text('Сначала собери мусор в совок.'), findsOneWidget);
      expect(find.byKey(const ValueKey('scene-room-kitchen')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('job-step')));
      expect(steps, ['sweep']);
      await tester.tap(find.byKey(const ValueKey('scene-menu')));
      expect(menus, 0);
      await tester.tap(find.byKey(const ValueKey('job-cancel')));
      expect(cancelled, 1);
      await show(
        const JobProgress(
          jobId: 'J06',
          title: 'Подмети пол',
          room: 'living',
          stage: 'awaiting_ack',
          completed: 6,
          total: 6,
        ),
      );
      expect(find.text('Сохраняем результат…'), findsOneWidget);
      expect(find.byKey(const ValueKey('job-feedback')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('job-step')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('job-cancel')))
            .onPressed,
        isNull,
      );
      await show(
        const JobProgress(
          jobId: 'J06',
          title: 'Подметём вместе',
          room: 'living',
          stage: 'idle',
          completed: 0,
          total: 6,
          nextStep: 'sweep',
        ),
      );
      expect(find.byKey(const ValueKey('job-step')), findsNothing);
      expect(find.byKey(const ValueKey('scene-job')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('room fills portrait screen and shared income updates the dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState()
      ..name = 'Персик'
      ..currentRoom = 'kitchen';
    var openedPlan = 0;
    var showedJob = 0;
    Future<void> show({bool busy = false}) => tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: GameHome(
            state: state,
            scene: const ColoredBox(
              key: ValueKey('full-room'),
              color: Colors.white,
            ),
            ready: true,
            busy: busy,
            onRoom: (_) {},
            onCare: () {},
            onLamp: () {},
            onPlan: () => openedPlan++,
            onShowJob: () => showedJob++,
            onMission: () {},
            onDream: () {},
            onNextDay: () {},
          ),
        ),
      ),
    );
    await show();
    expect(
      tester.getSize(find.byKey(const ValueKey('full-room'))),
      const Size(360, 800),
    );
    expect(find.text('Посуда'), findsOneWidget);
    expect(state.incomeAvailable, isTrue);
    expect(find.text('Спланируем игровой день'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene-show-next')));
    expect(openedPlan, 1);
    expect(showedJob, 0);
    state.confirmPlan([15, 5, 20]);
    await show();
    expect(find.text('Кухня · Помой посуду'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene-show-next')));
    expect(showedJob, 1);
    expect(state.wallet[0], 100);
    state.incomeClaimedDay = state.day;
    await show();
    expect(find.text('Посуда'), findsOneWidget);
    expect(state.incomeAvailable, isFalse);
    expect(find.text('Доход получен · уточни план'), findsOneWidget);
    expect(find.textContaining('+30'), findsNothing);
    state.currentRoom = 'living';
    await show();
    expect(find.text('Задание'), findsOneWidget);
    expect(state.incomeAvailable, isFalse);
    expect(find.byKey(const ValueKey('scene-lamp')), findsNothing);
    expect(find.byKey(const ValueKey('scene-drink')), findsNothing);
    state.lampOn = false;
    await show();
    expect(find.byKey(const ValueKey('scene-lamp')), findsNothing);
    await show(busy: true);
    expect(find.byKey(const ValueKey('scene-show-next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3D HUD supports large text and hamster-specific care', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState()
      ..name = 'Плюш'
      ..species = 2
      ..currentRoom = 'bathroom';
    var actions = 0, sceneTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: GameHome(
              state: state,
              scene: GestureDetector(
                key: const ValueKey('full-room-large'),
                behavior: HitTestBehavior.opaque,
                onTap: () => sceneTaps++,
                child: const ColoredBox(color: Colors.white),
              ),
              ready: true,
              busy: false,
              onRoom: (_) {},
              onCare: () => actions++,
              onLamp: () {},
              onPlan: () {},
              onMission: () {},
              onDream: () {},
              onNextDay: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Запас: ${state.wallet[2]} монет'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('full-room-large'))),
      const Size(320, 640),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('scene-reserve'))).dy,
      lessThan(640),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('scene-open-center'))),
    );
    expect(sceneTaps, 1);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('scene-care')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('scene-action-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Песочная ванночка · 5 монет'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene-care')));
    expect(actions, 1);
    expect(find.text('Задание · Награда: 30 монет'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dish HUD uses tactile stages and preserves coverage through rotation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = GameState()
        ..name = 'Плюш'
        ..currentRoom = 'kitchen';
      final steps = <String>[];
      const scrub = DishProgress(
        stage: 'scrub',
        cleaned: 5,
        coverage: DishCoverage(spots: [1, 1, 1, 1, 1, .4], foam: .82, rinse: 0),
      );
      var dish = scrub;

      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: GameHome(
                state: state,
                scene: const ColoredBox(color: Colors.white),
                ready: true,
                busy: false,
                dish: dish,
                onRoom: (_) {},
                onCare: () {},
                onLamp: () {},
                onPlan: () {},
                onMission: () {},
                onDream: () {},
                onNextDay: () {},
                onDishStep: steps.add,
                onCancelDish: () {},
              ),
            ),
          ),
        ),
      );

      await show();
      expect(find.text('Намыль тарелку'), findsOneWidget);
      expect(find.text('Осталось одно пятно'), findsOneWidget);
      expect(find.text('Намылить пятно'), findsOneWidget);
      expect(find.byKey(const ValueKey('scene-status-scroll')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('scene-action-scroll')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('dish-step'))).dy,
        lessThan(640),
      );
      await tester.tap(find.byKey(const ValueKey('dish-step')));
      expect(steps, ['scrub']);

      tester.view.physicalSize = const Size(640, 320);
      await tester.pump();
      await tester.pump();
      expect(find.text('Осталось одно пятно'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scene-landscape-actions')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      dish = const DishProgress(
        stage: 'rinse',
        cleaned: 6,
        waterOn: true,
        coverage: DishCoverage(
          spots: [1, 1, 1, 1, 1, 1],
          foam: .95,
          rinse: .62,
        ),
      );
      await show();
      expect(find.text('Смой пену'), findsOneWidget);
      expect(find.text('Смыто 62%'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('scene-landscape-actions')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('dish-step'))).dy,
        lessThan(320),
      );
      await tester.tap(find.byKey(const ValueKey('dish-step')));
      expect(steps, ['scrub', 'rinse']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker exposes every chore with reward and training preflight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    HouseholdJob? selected;
    Future<void> show({required bool incomeAvailable}) => tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: HouseholdJobPicker(
            currentRoom: 'living',
            incomeAvailable: incomeAvailable,
            planConfirmed: true,
            onSelected: (job) => selected = job,
          ),
        ),
      ),
    );

    await show(incomeAvailable: true);
    for (final job in householdJobs.values) {
      expect(
        find.byKey(ValueKey('job-picker-${job.id.toLowerCase()}')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('job-picker-${job.id.toLowerCase()}')),
      );
      expect(selected?.id, job.id);
    }
    expect(find.text('Награда: 30 монет'), findsNWidgets(6));

    await show(incomeAvailable: false);
    expect(find.text('Тренировка · без монет'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'portrait to landscape keeps active job and leaves a center work area at 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = GameState()
        ..name = 'Бублик'
        ..currentRoom = 'living';
      state.confirmPlan([20, 0, 10]);
      var sceneCreates = 0;
      final insets = <(double, double, double, double)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: GameHome(
                state: state,
                scene: _SceneProbe(onCreate: () => sceneCreates++),
                ready: true,
                busy: false,
                job: const JobProgress(
                  jobId: 'J06',
                  title: 'Подметём вместе',
                  room: 'living',
                  stage: 'active',
                  completed: 4,
                  total: 6,
                  nextStep: 'put_away',
                ),
                jobId: 'J06',
                jobTitle: 'Подметём вместе',
                jobRoom: 'living',
                onRoom: (_) {},
                onCare: () {},
                onLamp: () {},
                onPlan: () {},
                onMission: () {},
                onDream: () {},
                onNextDay: () {},
                onJob: () {},
                onJobStep: (_) {},
                onCancelJob: () {},
                onViewportInsets: (top, right, bottom, left) =>
                    insets.add((top, right, bottom, left)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(sceneCreates, 1);
      expect(find.text('Верни веник на место.'), findsOneWidget);
      expect(find.byKey(const ValueKey('scene-status-scroll')), findsNothing);
      expect(insets.last.$1, closeTo(.04, .0001));
      expect(insets.last.$2, 0);
      expect(insets.last.$3, closeTo(.415, .0001));
      expect(insets.last.$4, 0);
      expect(
        tester.getSize(find.byKey(const ValueKey('scene-open-center'))).height,
        greaterThan(400),
      );

      tester.view.physicalSize = const Size(800, 400);
      await tester.pump();
      await tester.pump();
      expect(sceneCreates, 1);
      expect(
        find.byKey(const ValueKey('scene-landscape-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scene-landscape-actions')),
        findsOneWidget,
      );
      expect(find.text('Верни веник на место.'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('rotation-scene'))),
        const Size(800, 400),
      );
      expect(insets.last.$1, 0);
      expect(insets.last.$2, closeTo(.315, .0001));
      expect(insets.last.$3, 0);
      expect(insets.last.$4, closeTo(.315, .0001));
      expect(
        tester.getSize(find.byKey(const ValueKey('scene-open-center'))).width,
        greaterThan(100),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('640x360 notched landscape keeps a 48px task work area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState()
      ..name = 'Плюш'
      ..currentRoom = 'living';
    state.confirmPlan([20, 0, 10]);
    (double, double, double, double)? insets;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(left: 32, right: 24),
              textScaler: TextScaler.linear(2),
            ),
            child: GameHome(
              state: state,
              scene: const ColoredBox(color: Colors.white),
              ready: true,
              busy: false,
              job: const JobProgress(
                jobId: 'J02',
                title: 'Всё на месте',
                room: 'living',
                stage: 'active',
                completed: 1,
                total: 3,
                nextStep: 'sort',
              ),
              jobId: 'J02',
              jobTitle: 'Всё на месте',
              jobRoom: 'living',
              onRoom: (_) {},
              onCare: () {},
              onLamp: () {},
              onPlan: () {},
              onMission: () {},
              onDream: () {},
              onNextDay: () {},
              onJob: () {},
              onJobStep: (_) {},
              onCancelJob: () {},
              onViewportInsets: (top, right, bottom, left) =>
                  insets = (top, right, bottom, left),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(insets?.$2, closeTo(.33, .0001));
    expect(insets?.$4, closeTo(.3425, .0001));
    expect(
      tester.getSize(find.byKey(const ValueKey('scene-open-center'))).width,
      greaterThanOrEqualTo(48),
    );
    expect(find.byKey(const ValueKey('job-step')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('HUD viewport insets match portrait and notched landscape panels', () {
    final portrait = GameHudGeometry.resolve(
      const Size(432, 768),
      EdgeInsets.zero,
      accessible: false,
    );
    expect(
      (portrait.top, portrait.right, portrait.bottom, portrait.left),
      (.13, 0, .19, 0),
    );
    final portraitLarge = GameHudGeometry.resolve(
      const Size(432, 768),
      EdgeInsets.zero,
      accessible: true,
    );
    expect(
      (
        portraitLarge.top,
        portraitLarge.right,
        portraitLarge.bottom,
        portraitLarge.left,
      ),
      (.38, 0, .40, 0),
    );
    final portraitLargeTask = GameHudGeometry.resolve(
      const Size(432, 768),
      EdgeInsets.zero,
      accessible: true,
      activeMinigame: true,
    );
    expect(portraitLargeTask.top, closeTo(.04, .0001));
    expect(portraitLargeTask.right, 0);
    expect(portraitLargeTask.bottom, closeTo(.415625, .0001));
    expect(portraitLargeTask.left, 0);
    final portraitLargeTaskWithSafeArea = GameHudGeometry.resolve(
      const Size(432, 768),
      const EdgeInsets.only(top: 32, bottom: 24),
      accessible: true,
      activeMinigame: true,
    );
    expect(portraitLargeTaskWithSafeArea.top, closeTo(44 / 768, .0001));
    expect(
      portraitLargeTaskWithSafeArea.bottom,
      closeTo((24 + 12 + .40 * 712) / 768, .0001),
    );
    expect(
      portraitLargeTaskWithSafeArea.top + portraitLargeTaskWithSafeArea.bottom,
      lessThan(.85),
    );

    for (final accessible in [false, true]) {
      final wide = GameHudGeometry.resolve(
        const Size(960, 540),
        EdgeInsets.zero,
        accessible: accessible,
      );
      expect(wide.right, closeTo(.3125, .0001));
      expect(wide.left, closeTo(.3125, .0001));
      expect(wide.right + wide.left, lessThan(.75));
    }

    final notched = GameHudGeometry.resolve(
      const Size(640, 360),
      const EdgeInsets.only(left: 32, right: 24),
      accessible: true,
    );
    expect(notched.panelWidth, closeTo(175.2, .0001));
    expect(notched.left, closeTo(.3425, .0001));
    expect(notched.right, closeTo(.33, .0001));
    expect(notched.left + notched.right, lessThan(.75));
    expect(640 * (1 - notched.left - notched.right), greaterThanOrEqualTo(48));
  });
}
