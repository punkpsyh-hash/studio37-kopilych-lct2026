import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// Each bounded request owns and frees its native model inside an isolate.
// This keeps the UI responsive and avoids retaining both large models at rest.
Future<List<double>> synthesizeSpeech(
  String root,
  String text,
  String output,
) => Isolate.run(() {
  sherpa.initBindings();
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$root/tts/model.onnx',
          tokens: '$root/tts/tokens.txt',
          dataDir: '$root/tts/espeak-ng-data',
        ),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  try {
    final audio = tts.generate(text: text, sid: 0, speed: 1.0);
    if (audio.samples.isEmpty) {
      throw StateError('Не удалось произнести реплику.');
    }
    sherpa.writeWave(
      filename: output,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    final step = (audio.sampleRate * .08).round();
    return [
      for (var i = 0; i < audio.samples.length; i += step)
        (math.sqrt(
                  audio.samples
                          .skip(i)
                          .take(step)
                          .fold<double>(0, (a, b) => a + b * b) /
                      math.min(step, audio.samples.length - i),
                ) *
                8)
            .clamp(0.0, 1.0),
    ];
  } finally {
    tts.free();
  }
});

Future<String> recognizeSpeech(String root, String input) => Isolate.run(() {
  sherpa.initBindings();
  final wave = sherpa.readWave(input);
  if (!hasSpeechInput(wave.samples, wave.sampleRate)) return '';
  // Subsampling needs sufficient feature frames, even for a short utterance.
  final padded = Float32List(wave.samples.length + wave.sampleRate ~/ 2)
    ..setRange(0, wave.samples.length, wave.samples);
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        transducer: sherpa.OfflineTransducerModelConfig(
          encoder: '$root/asr/encoder.onnx',
          decoder: '$root/asr/decoder.onnx',
          joiner: '$root/asr/joiner.onnx',
        ),
        tokens: '$root/asr/tokens.txt',
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: padded, sampleRate: wave.sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
    recognizer.free();
  }
});

bool hasSpeechInput(Float32List samples, int sampleRate) {
  if (sampleRate <= 0 || samples.length < sampleRate * .35) return false;
  var peak = 0.0;
  for (final sample in samples) {
    if (!sample.isFinite) return false;
    peak = math.max(peak, sample.abs());
  }
  return peak >= .003;
}
