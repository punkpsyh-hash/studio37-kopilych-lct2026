import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kopilych/local_voice.dart';
import 'package:kopilych/story_dialogue.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Bundled Russian models synthesize and recognize offline',
    (tester) async {
      final voice = LocalVoice();
      try {
        await tester.runAsync(() async {
          final root = await voice.prepare();
          final temp = await getTemporaryDirectory();
          final speech = '${temp.path}/voice-integration.wav';
          final results = <String>[];
          for (final phrase in ['Первый вариант', 'Второй вариант']) {
            final envelope = await synthesizeSpeech(root, phrase, speech);
            expect(envelope, isNotEmpty);
            expect(envelope.any((v) => v > .05), isTrue);
            expect(await File(speech).length(), greaterThan(10000));
            final recognized = await recognizeSpeech(root, speech);
            results.add('$phrase → $recognized');
            expect(
              matchDialogueChoice(recognized, dialogueScenes.first.choices),
              phrase.startsWith('Первый') ? 0 : 1,
            );
          }
          final preview =
              '${(await getApplicationSupportDirectory()).path}/voice-preview.wav';
          await synthesizeSpeech(
            root,
            'Привет! Давай устроим наш дом. Сначала позаботимся о нужном, а потом выберем мечту.',
            preview,
          );
          await File(
            '${(await getApplicationSupportDirectory()).path}/voice-test-result.txt',
          ).writeAsString(results.join('\n'));
          await File(speech).delete();
          await voice.say('Привет!');
          expect(voice.speaking, isTrue);
          await voice.stop();
          expect(voice.speaking, isFalse);
          expect(voice.listening, isFalse);
          expect(voice.mouth, 0);
          final interrupted = voice.say(
            'Давай сначала составим план на несколько дней.',
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await voice.stop();
          await interrupted;
          expect(voice.speaking, isFalse);
          expect(voice.busy, isFalse);
        });
      } finally {
        voice.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'Emulator microphone is cancellable, bounded and leaves no recording',
    (tester) async {
      // Run only with RECORD_AUDIO granted to the test package on an emulator
      // launched with -no-audio. This does not capture the host microphone.
      if (!const bool.fromEnvironment('TEST_MIC')) return;
      final voice = LocalVoice();
      try {
        await tester.runAsync(() async {
          await voice.startListening(() {});
          expect(voice.listening, isTrue);
          await voice.stop();
          expect(voice.listening, isFalse);
          final limit = Completer<void>();
          await voice.startListening(() async {
            try {
              await voice.finishListening();
              limit.complete();
            } catch (error, stack) {
              limit.completeError(error, stack);
            }
          });
          await limit.future.timeout(const Duration(seconds: 35));
          expect(voice.listening, isFalse);
          expect(voice.busy, isFalse);
          final files = (await getTemporaryDirectory())
              .listSync()
              .whereType<File>()
              .where((f) => f.path.split('/').last.startsWith('pet-input-'));
          expect(files, isEmpty);
        });
      } finally {
        voice.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
