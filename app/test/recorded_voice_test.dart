import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/story_dialogue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every current dialogue and hint has a matching offline recording',
    () async {
      final data =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/voice/elevenlabs-dylan/catalog.json',
                ),
              )
              as Map<String, dynamic>;
      final clips = data['clips'] as Map<String, dynamic>;
      final expected = <String, String>{};
      for (var chapter = 0; chapter < dialogueScenes.length; chapter++) {
        final prefix = 'chapter_${(chapter + 1).toString().padLeft(2, '0')}';
        final scene = dialogueScenes[chapter];
        for (var line = 0; line < scene.lines.length; line++) {
          expected['$prefix.line_${(line + 1).toString().padLeft(2, '0')}'] =
              scene.lines[line];
        }
        for (var choice = 0; choice < scene.choices.length; choice++) {
          expected['$prefix.choice_${(choice + 1).toString().padLeft(2, '0')}.reply'] =
              scene.choices[choice].reply;
        }
        expected['$prefix.hint'] = dialogueHints[chapter];
      }
      expect(clips.length, expected.length);
      for (final entry in expected.entries) {
        final clip = clips[entry.key] as Map<String, dynamic>;
        expect(clip['text'], entry.value, reason: entry.key);
        expect(
          (clip['envelope'] as List).isNotEmpty,
          isTrue,
          reason: entry.key,
        );
        final audio = await rootBundle.load(
          'assets/voice/elevenlabs-dylan/${entry.key}.mp3',
        );
        expect(audio.lengthInBytes, greaterThan(1000), reason: entry.key);
      }
    },
  );
}
