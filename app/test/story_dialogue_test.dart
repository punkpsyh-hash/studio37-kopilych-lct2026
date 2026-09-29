import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/dialogue_page.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/story_dialogue.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/ui.dart';

void main() {
  test('Voice proposes only an unambiguous authored choice', () {
    final choices = dialogueScenes.first.choices;
    expect(matchDialogueChoice('Первый вариант!', choices), 0);
    expect(matchDialogueChoice('второй', choices), 1);
    expect(matchDialogueChoice('Составим план', choices), 0);
    for (final text in [
      '',
      'не первый вариант',
      'первый или второй',
      'купи за сто',
      'третий',
    ]) {
      expect(matchDialogueChoice(text, choices), isNull);
    }
  });

  testWidgets('All six conversations work silently and preserve the wallet', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final state = GameState()
      ..name = 'Листик'
      ..reducedMotion = true;
    final total = state.total;
    for (var chapter = 0; chapter < dialogueScenes.length; chapter++) {
      var continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DialoguePage(
            key: ValueKey(chapter),
            state: state,
            chapter: chapter,
            onContinue: () => continued = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(SharedRoom)),
        const Rect.fromLTWH(0, 0, 800, 600),
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
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap('Дальше');
      await tap('Дальше');
      await tap('Объясни проще');
      expect(find.text(dialogueHints[chapter]), findsOneWidget);
      await tap('К реплике');
      await tap('1. ${dialogueScenes[chapter].choices[0].label}');
      expect(
        find.text(dialogueScenes[chapter].choices[0].reply),
        findsOneWidget,
      );
      await tap('Обсудить другой вариант');
      await tap('2. ${dialogueScenes[chapter].choices[1].label}');
      expect(
        find.text(dialogueScenes[chapter].choices[1].reply),
        findsOneWidget,
      );
      await tap('К заданию главы');
      expect(continued, isTrue);
      expect(state.total, total);
      expect(state.completed, isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Conversation choices stay reachable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: DialoguePage(
          state: GameState()..name = 'Листик',
          chapter: 0,
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(SharedRoom)),
      const Rect.fromLTWH(0, 0, 320, 640),
    );
    for (final label in [
      'Дальше',
      'Дальше',
      '1. Составим план',
      'К заданию главы',
    ]) {
      final finder = find.text(label);
      await tester.scrollUntilVisible(
        finder,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(continued, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
