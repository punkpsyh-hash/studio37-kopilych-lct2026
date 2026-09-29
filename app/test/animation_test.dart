import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/art.dart';

void main() {
  testWidgets('Switching motion back on cannot leave a static reaction stuck', (
    tester,
  ) async {
    Widget scene(int event, bool reduced, PetAction action) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 310,
          child: PetScene(
            species: 1,
            color: 4,
            reaction: event,
            action: action,
            reducedMotion: reduced,
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene(0, true, PetAction.idle));
    await tester.pumpWidget(scene(1, true, PetAction.feed));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(scene(2, false, PetAction.play));
    await tester.pump(const Duration(seconds: 3));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<PetPainter>()
        .single;
    expect(painter.action, PetAction.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  PetPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<PetPainter>()
      .single;
  Widget scene(int event, PetAction action, {bool reduced = false}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 310,
            child: PetScene(
              species: 0,
              color: 0,
              reaction: event,
              action: action,
              reducedMotion: reduced,
            ),
          ),
        ),
      );
  testWidgets('Care reaction finishes and repeated event does not replay', (
    tester,
  ) async {
    await tester.pumpWidget(scene(0, PetAction.idle));
    await tester.pumpWidget(scene(1, PetAction.feed));
    await tester.pump(const Duration(milliseconds: 700));
    expect(painter(tester).action, PetAction.feed);
    expect(painter(tester).actionProgress, greaterThan(0));
    await tester.pump(const Duration(seconds: 3));
    expect(painter(tester).action, PetAction.idle);
    await tester.pumpWidget(scene(1, PetAction.feed));
    expect(painter(tester).action, PetAction.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Reduced motion shows static feedback then returns to idle', (
    tester,
  ) async {
    await tester.pumpWidget(scene(0, PetAction.idle, reduced: true));
    await tester.pumpWidget(scene(1, PetAction.bath, reduced: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter(tester).action, PetAction.bath);
    expect(painter(tester).actionProgress, .42);
    expect(painter(tester).phase, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter(tester).actionProgress, .42);
    await tester.pump(const Duration(seconds: 2));
    expect(painter(tester).action, PetAction.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'A new action interrupts the previous clip without queued effects',
    (tester) async {
      await tester.pumpWidget(scene(0, PetAction.idle));
      await tester.pumpWidget(scene(1, PetAction.play));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(scene(2, PetAction.love));
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter(tester).action, PetAction.love);
      expect(painter(tester).actionProgress, lessThan(.2));
      await tester.pump(const Duration(seconds: 3));
      expect(painter(tester).action, PetAction.idle);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
