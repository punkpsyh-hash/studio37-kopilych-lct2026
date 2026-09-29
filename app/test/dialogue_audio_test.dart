import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/dialogue_page.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/local_voice.dart';
import 'package:kopilych/story_dialogue.dart';

class _FakeVoice extends ChangeNotifier implements VoiceSession {
  final spoken = <(String, String?)>[];
  @override
  bool busy = false;
  @override
  bool listening = false;
  @override
  bool speaking = false;

  @override
  Future<void> say(String text, {String? clipId}) async {
    spoken.add((text, clipId));
    speaking = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    speaking = false;
    notifyListeners();
  }

  @override
  Future<void> startListening(VoidCallback onTimeLimit) async {
    listening = true;
    notifyListeners();
  }

  @override
  Future<String> finishListening() async {
    listening = false;
    notifyListeners();
    return '';
  }
}

void main() {
  testWidgets('story lines, replies and hints speak when displayed', (
    tester,
  ) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: DialoguePage(
          state: GameState()..name = 'Листик',
          chapter: 0,
          onContinue: () {},
          voiceFactory: () => voice,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(voice.spoken, [(dialogueScenes[0].lines[0], 'chapter_01.line_01')]);

    Future<void> tap(String label) async {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          120,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await Scrollable.ensureVisible(finder.evaluate().single, alignment: .35);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap('Дальше');
    expect(voice.spoken.last, (
      dialogueScenes[0].lines[1],
      'chapter_01.line_02',
    ));
    await tap('Объясни проще');
    expect(voice.spoken.last, (dialogueHints[0], 'chapter_01.hint'));
    await tap('К реплике');
    await tap('Дальше');
    await tap('1. ${dialogueScenes[0].choices[0].label}');
    expect(voice.spoken.last, (
      dialogueScenes[0].choices[0].reply,
      'chapter_01.choice_01.reply',
    ));
    await tap('Без звука');
    final count = voice.spoken.length;
    await tap('Обсудить другой вариант');
    expect(voice.spoken.length, count);
    await tap('Послушать');
    expect(voice.spoken.length, count + 1);
  });

  testWidgets('canonical override uses offline synthesis text', (tester) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: DialoguePage(
          state: GameState()..name = 'Листик',
          chapter: 0,
          sceneOverride: canonicalDialogueScenes[0],
          hintOverride: canonicalDialogueHints[0],
          onContinue: () {},
          voiceFactory: () => voice,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(voice.spoken.single, (canonicalDialogueScenes[0].lines[0], null));
  });

  testWidgets('voice setting keeps the dialogue silent and readable', (
    tester,
  ) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: DialoguePage(
          state: GameState()..name = 'Листик',
          chapter: 0,
          onContinue: () {},
          voiceFactory: () => voice,
          voiceEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(voice.spoken, isEmpty);
    expect(find.text(dialogueScenes[0].lines[0]), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Послушать'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final listenButton = find.ancestor(
      of: find.text('Послушать'),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(tester.widget<TextButton>(listenButton).onPressed, isNull);
  });
}
