import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('volume defaults to full and persists independently of mute', () {
    final state = GameState()
      ..soundEnabled = false
      ..soundVolume = 35;
    final saved = state.toJson();
    expect(saved['soundVolume'], 35);
    final restored = GameState.fromJson(saved);
    expect(restored.soundEnabled, isFalse);
    expect(restored.soundVolume, 35);

    final legacy = Map<String, dynamic>.from(saved)..remove('soundVolume');
    expect(GameState.fromJson(legacy).soundVolume, 100);
    for (final entry in [(-10, 0), (120, 100)]) {
      expect(
        GameState.fromJson({...saved, 'soundVolume': entry.$1}).soundVolume,
        entry.$2,
      );
    }
    expect(
      GameState.fromJson({...saved, 'soundVolume': 'bad'}).soundVolume,
      100,
    );
    expect(
      () => (GameState()..soundVolume = 101).validate(),
      throwsFormatException,
    );
  });

  test('room bridge sends user volume to the scene', () {
    final room = File('lib/shared_room.dart').readAsStringSync();
    final shell = File('lib/shell.dart').readAsStringSync();
    expect(room, contains("_call('setSoundVolume', widget.soundVolume)"));
    expect(shell, contains('soundVolume: _soundVolumeDraft ?? s.soundVolume'));
  });

  test('volume survives storage and demo resets', () async {
    final store = await GameStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      await store.change('volume:35', 'Громкость', (state) {
        state.soundVolume = 35;
      });
      expect((await store.load()).soundVolume, 35);
      expect((await store.startDemo()).soundVolume, 35);
      expect((await store.resetDemo()).soundVolume, 35);
      expect((await store.exitDemo()).soundVolume, 35);
    } finally {
      await store.close();
    }
  });

  testWidgets('sheet shows draft and rolls back a failed save', (tester) async {
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    final controller = GameController(store!);
    addTearDown(() async {
      controller.dispose();
      await tester.runAsync(store.close);
    });
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller, useMeshyModels: false),
      ),
    );
    final dynamic shellState = tester.state(find.byType(GameShell));
    shellState.settings();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Громкость звуков: 100%'), findsOneWidget);

    Slider slider() => tester.widget<Slider>(find.byType(Slider).last);
    slider().onChanged!(35);
    await tester.pump();
    expect(find.text('Громкость звуков: 35%'), findsOneWidget);
    await tester.runAsync(() async {
      await (slider().onChangeEnd as dynamic)(35.0);
    });
    await tester.pump();
    expect(controller.state!.soundVolume, 35);
    expect(find.text('Громкость звуков: 35%'), findsOneWidget);

    await tester.runAsync(
      () => store.db.execute(
        "CREATE TRIGGER fail_volume BEFORE UPDATE ON state BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      ),
    );
    slider().onChanged!(70);
    await tester.pump();
    expect(find.text('Громкость звуков: 70%'), findsOneWidget);
    await tester.runAsync(() async {
      await (slider().onChangeEnd as dynamic)(70.0);
    });
    await tester.pump();
    expect(controller.state!.soundVolume, 35);
    expect(find.text('Громкость звуков: 35%'), findsOneWidget);
  });
}
