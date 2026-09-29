import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/scene_bridge.dart';
import 'package:kopilych/ui.dart';

Widget _roomPlaceholder() => const ColoredBox(
  color: Color(0xFFD7C8A5),
  child: Center(
    child: Text(
      '3D-КОМНАТА · HUD PREVIEW · NOT ANDROID',
      style: TextStyle(
        color: Color(0xFF78694F),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
);

GameState _state() {
  final state = GameState()
    ..name = 'Бублик'
    ..currentRoom = 'living';
  state.confirmPlan([20, 0, 10]);
  return state;
}

Widget _preview({required bool activeJob, double textScale = 1}) {
  final state = _state();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(
          key: const ValueKey('hud-golden'),
          child: GameHome(
            state: state,
            scene: _roomPlaceholder(),
            ready: true,
            busy: false,
            job: activeJob
                ? const JobProgress(
                    jobId: 'J06',
                    title: 'Подметём вместе',
                    room: 'living',
                    stage: 'active',
                    completed: 4,
                    total: 6,
                    nextStep: 'put_away',
                  )
                : const JobProgress(),
            jobId: 'J06',
            jobTitle: 'Подметём вместе',
            jobRoom: 'living',
            taskFeedback: activeJob
                ? null
                : 'Игрушки на месте! Награда: +30 монет.',
            onRoom: (_) {},
            onCare: () {},
            onLamp: () {},
            onPlan: () {},
            onMission: () {},
            onDream: () {},
            onNextDay: () {},
            onJob: () {},
            onShowJob: () {},
            onJobStep: (_) {},
            onCancelJob: () {},
            onDismissFeedback: () {},
          ),
        ),
      ),
    ),
  );
}

Widget _dishPreview() {
  final state = _state()..currentRoom = 'kitchen';
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('hud-golden'),
        child: GameHome(
          state: state,
          scene: _roomPlaceholder(),
          ready: true,
          busy: false,
          dish: const DishProgress(
            stage: 'rinse',
            cleaned: 6,
            waterOn: true,
            coverage: DishCoverage(
              spots: [1, 1, 1, 1, 1, 1],
              foam: .44,
              rinse: .62,
            ),
          ),
          onRoom: (_) {},
          onCare: () {},
          onLamp: () {},
          onPlan: () {},
          onMission: () {},
          onDream: () {},
          onNextDay: () {},
          onDishStep: (_) {},
          onCancelDish: () {},
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final nunito = FontLoader('Nunito');
    for (final weight in [400, 600, 800, 900]) {
      nunito.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    await nunito.load();
  });

  testWidgets('notAndroid portrait minigame HUD', (tester) async {
    tester.view.physicalSize = const Size(432, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_preview(activeJob: false));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('hud-golden')),
      matchesGoldenFile(
        'goldens/minigame-ui/notAndroid-game-home-portrait-432x768.png',
      ),
    );
  });

  testWidgets('notAndroid portrait active HUD at 200% text', (tester) async {
    tester.view.physicalSize = const Size(432, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_preview(activeJob: true, textScale: 2));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('hud-golden')),
      matchesGoldenFile(
        'goldens/minigame-ui/notAndroid-game-home-portrait-432x768-text200-active.png',
      ),
    );
  });

  testWidgets('notAndroid landscape active minigame HUD', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_preview(activeJob: true));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('hud-golden')),
      matchesGoldenFile(
        'goldens/minigame-ui/notAndroid-game-home-landscape-960x540.png',
      ),
    );
  });

  testWidgets('notAndroid landscape active HUD at 200% text', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_preview(activeJob: true, textScale: 2));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('hud-golden')),
      matchesGoldenFile(
        'goldens/minigame-ui/notAndroid-game-home-landscape-960x540-text200.png',
      ),
    );
  });

  testWidgets('notAndroid landscape dish rinse HUD', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_dishPreview());
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('hud-golden')),
      matchesGoldenFile(
        'goldens/minigame-ui/notAndroid-game-home-landscape-dish-rinse-960x540.png',
      ),
    );
  });
}
