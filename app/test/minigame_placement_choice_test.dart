import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/scene_bridge.dart';
import 'package:kopilych/ui.dart';

const sources = [
  JobPlacementOption('single_book', 'Книга 1'),
  JobPlacementOption('teddy_toy', 'Мишка'),
];
const targets = [
  JobPlacementOption('living_shelf_low', 'Нижняя полка'),
  JobPlacementOption('living_shelf_high', 'Верхняя полка'),
  JobPlacementOption('toy_chest', 'Сундук'),
];

Widget home({
  required void Function(String, String) onPlace,
  required ValueChanged<String> onStep,
  bool busy = false,
  double textScale = 1,
}) {
  final state = GameState()..currentRoom = 'living';
  state.confirmPlan([20, 0, 10]);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: GameHome(
        state: state,
        scene: const ColoredBox(
          key: ValueKey('full-room'),
          color: Color(0xFFD7C8A5),
          child: Center(child: Text('HUD PREVIEW · NOT ANDROID')),
        ),
        ready: true,
        busy: false,
        job: JobProgress(
          jobId: 'J02',
          title: 'Всё на месте',
          room: 'living',
          stage: 'active',
          total: 3,
          nextStep: 'sort',
          placementSources: sources,
          placementTargets: targets,
          placementBusy: busy,
        ),
        onRoom: (_) {},
        onCare: () {},
        onLamp: () {},
        onPlan: () {},
        onMission: () {},
        onDream: () {},
        onNextDay: () {},
        onJobStep: onStep,
        onJobPlacement: onPlace,
        onCancelJob: () {},
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Nunito');
    for (final weight in [400, 600, 800, 900]) {
      font.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    await font.load();
  });
  test(
    'placement progress preserves explicit choices and rejects malformed lists',
    () {
      final message = <String, dynamic>{
        'type': 'minigame',
        'game': 'household_job',
        'jobId': 'J04',
        'title': 'Разберём упаковки',
        'room': 'kitchen',
        'stage': 'active',
        'completed': 0,
        'total': 4,
        'nextStep': 'sort',
        'placement': {
          'busy': false,
          'sources': [
            {'id': 'package_star', 'label': 'Звезда'},
          ],
          'targets': [
            {'id': 'bin_circle', 'label': 'Круг'},
            {'id': 'bin_star', 'label': 'Звезда'},
          ],
        },
      };
      final parsed = JobProgress.parse(message)!;
      expect(parsed.placementSources.single.id, 'package_star');
      expect(parsed.placementTargets.map((p) => p.id), [
        'bin_circle',
        'bin_star',
      ]);
      final placement = message['placement'] as Map<String, dynamic>;
      for (final invalid in [
        {...placement, 'busy': 'false'},
        {
          ...placement,
          'sources': [
            {'id': 'package_star', 'label': ''},
          ],
        },
        {
          ...placement,
          'targets': List.filled(2, {'id': 'bin_star', 'label': 'Звезда'}),
        },
        {
          ...placement,
          'targets': [
            {'id': '<script>', 'label': 'Звезда'},
          ],
        },
      ]) {
        expect(JobProgress.parse({...message, 'placement': invalid}), isNull);
      }
      expect(JobProgress.parse({...message}..remove('placement')), isNotNull);
    },
  );

  for (final (size, scale) in [
    (const Size(432, 768), 1.0),
    (const Size(640, 360), 2.0),
  ]) {
    testWidgets('child chooses both source and destination at $size/$scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final placements = <(String, String)>[], autoSteps = <String>[];
      await tester.pumpWidget(
        home(
          onPlace: (source, target) => placements.add((source, target)),
          onStep: autoSteps.add,
          textScale: scale,
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('job-step')));
      await tester.tap(find.byKey(const ValueKey('job-step')));
      await tester.pumpAndSettle();
      expect(placements, isEmpty);
      expect(autoSteps, isEmpty);
      expect(
        find.byKey(const ValueKey('job-target-living_shelf_high')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('job-source-single_book')));
      await tester.pumpAndSettle();
      final destination = find.byKey(
        const ValueKey('job-target-living_shelf_high'),
      );
      await tester.ensureVisible(destination);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/minigame-ui/placement-choice-${size.width > size.height ? 'landscape-large' : 'portrait'}.png',
        ),
      );
      expect(tester.getSize(destination).height, greaterThanOrEqualTo(48));
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(placements, [('single_book', 'living_shelf_high')]);
      expect(autoSteps, isEmpty);
      expect(
        find.byKey(const ValueKey('job-placement-question')),
        findsNothing,
      );
      expect(tester.getSize(find.byKey(const ValueKey('full-room'))), size);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('in-flight placement cannot open a second chooser', (
    tester,
  ) async {
    await tester.pumpWidget(
      home(onPlace: (_, _) {}, onStep: (_) {}, busy: true),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('job-step')))
          .onPressed,
      isNull,
    );
  });
}
