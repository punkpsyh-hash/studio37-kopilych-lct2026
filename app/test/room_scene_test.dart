import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/art.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/room_scene.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('Room navigation keeps the chosen pet and care saves once', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    await tester.runAsync(
      () => store!.change('setup', 'First pet', (state) {
        state.name = 'Листик';
        state.species = 2;
        state.color = 3;
        state.reducedMotion = true;
      }),
    );
    final controller = GameController(store!);
    await tester.runAsync(controller.load);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );

    expect(
      tester.widget<RoomStage>(find.byType(RoomStage)).room,
      HomeRoom.living,
    );
    await tester.tap(find.text('Кухня'));
    await tester.pump();
    expect(
      tester.widget<RoomStage>(find.byType(RoomStage)).room,
      HomeRoom.kitchen,
    );
    expect(tester.widget<PetScene>(find.byType(PetScene)).species, 2);

    await tester.tap(find.text('Кормить · 10'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; controller.busy && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(controller.busy, isFalse);
    expect(controller.state!.wallet[0], 90);
    expect(controller.state!.needs[0], 85);
    expect(
      tester.widget<PetScene>(find.byType(PetScene)).action,
      PetAction.feed,
    );

    final playedReaction = tester
        .widget<PetScene>(find.byType(PetScene))
        .reaction;
    await tester.runAsync(
      () => controller.change('need full', (state) => state.needs[0] = 100),
    );
    await tester.pump();
    await tester.tap(find.text('Кормить · 10'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; controller.busy && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    // Canon: a repeat feed on the same day is a free visual replay.
    expect(controller.state!.wallet[0], 90);
    expect(controller.state!.needs[0], 100);
    expect(
      tester.widget<PetScene>(find.byType(PetScene)).reaction,
      isNot(playedReaction),
    );

    await tester.tap(find.text('Ванная'));
    await tester.pump();
    expect(
      tester.widget<RoomStage>(find.byType(RoomStage)).room,
      HomeRoom.bathroom,
    );
    expect(tester.widget<PetScene>(find.byType(PetScene)).species, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(store.close);
  });
}
