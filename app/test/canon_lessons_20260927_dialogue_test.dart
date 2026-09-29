import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/dialogue_page.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/story.dart';
import 'package:kopilych/story_dialogue.dart';

void main() {
  test('canonical dialogue is separate from the recorded legacy script', () {
    expect(canonicalDialogueScenes, hasLength(6));
    expect(canonicalDialogueHints, hasLength(6));
    final chapters = storyChapters(GameState()..name = 'Персик');
    expect(canonicalDialogueScenes, hasLength(chapters.length));
    expect(canonicalDialogueScenes[2].title, chapters[2].title);
    expect(canonicalDialogueScenes[3].title, chapters[3].title);
    expect(canonicalDialogueScenes.last.lines.join(' '), contains('Оба пути'));
    expect(
      dialogueScenes.last.lines.join(' '),
      contains('вещь, которую мы выбрали'),
      reason: 'the shipped recorded transcript remains unchanged',
    );
  });

  testWidgets('DialoguePage renders a canonical override and its hint', (
    tester,
  ) async {
    final scene = canonicalDialogueScenes.last;
    await tester.pumpWidget(
      MaterialApp(
        home: DialoguePage(
          state: GameState()..name = 'Персик',
          chapter: 5,
          sceneOverride: scene,
          hintOverride: canonicalDialogueHints.last,
          onContinue: () {},
        ),
      ),
    );

    expect(find.text(scene.title), findsOneWidget);
    expect(find.text(scene.lines.first), findsOneWidget);

    await tester.tap(find.text('Объясни проще'));
    await tester.pump();
    expect(find.text(canonicalDialogueHints.last), findsOneWidget);
  });

  testWidgets('canonical conversation continues without changing money', (
    tester,
  ) async {
    final state = GameState()..name = 'Персик';
    final before = List<int>.of(state.wallet);
    var continued = false;
    final scene = canonicalDialogueScenes[2];
    await tester.pumpWidget(
      MaterialApp(
        home: DialoguePage(
          state: state,
          chapter: 2,
          sceneOverride: scene,
          hintOverride: canonicalDialogueHints[2],
          onContinue: () => continued = true,
        ),
      ),
    );

    Future<void> tap(String label) async {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder.hitTestable());
      await tester.pumpAndSettle();
    }

    for (var line = 1; line < scene.lines.length; line++) {
      await tap('Дальше');
    }
    await tap('1. ${scene.choices.first.label}');
    await tap('К заданию главы');

    expect(continued, isTrue);
    expect(state.wallet, before);
  });
}
