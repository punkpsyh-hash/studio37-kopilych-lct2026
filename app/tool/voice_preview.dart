import 'dart:io';
import 'dart:ffi';
import 'package:kopilych/voice_models.dart';

Future<void> main() async {
  if (Platform.isWindows) {
    // Preload the matching ORT before Windows resolves its system copy.
    DynamicLibrary.open(
      '${Platform.environment['PUB_CACHE']}/hosted/pub.dev/sherpa_onnx_windows-1.13.8/windows/onnxruntime.dll',
    );
  }
  final root = Directory('assets/voice').absolute.path;
  final out = Directory('../outputs/voice').absolute;
  await out.create(recursive: true);
  await synthesizeSpeech(
    root,
    'Привет! Давай устроим наш дом. Сначала позаботимся о нужном, а потом выберем мечту.',
    '${out.path}/pet-voice-preview.wav',
  );
  final results = <String>[];
  for (final text in ['Первый вариант', 'Второй вариант']) {
    final file = '${out.path}/command-${results.length + 1}.wav';
    await synthesizeSpeech(root, text, file);
    results.add('$text → ${await recognizeSpeech(root, file)}');
  }
  await File(
    '${out.path}/recognition-test.txt',
  ).writeAsString(results.join('\n'));
  stdout.writeln(results.join('\n'));
}
