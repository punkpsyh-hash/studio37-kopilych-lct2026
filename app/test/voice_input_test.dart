import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/voice_models.dart';
import 'package:kopilych/pet_motion.dart';

void main() {
  test('Empty, tiny, silent and invalid audio never enters native decoder', () {
    expect(hasSpeechInput(Float32List(0), 16000), isFalse);
    expect(
      hasSpeechInput(Float32List.fromList(List.filled(320, .5)), 16000),
      isFalse,
    );
    expect(hasSpeechInput(Float32List(16000), 16000), isFalse);
    final signal = Float32List.fromList(List.filled(16000, .05));
    expect(hasSpeechInput(signal, 16000), isTrue);
    signal[10] = double.nan;
    expect(hasSpeechInput(signal, 16000), isFalse);
  });

  test(
    'Ball is continuous at catch, release and bounce and stays above the floor',
    () {
      for (final time in [.14, .25, .42, .76, .92]) {
        expect(
          playBallPosition(
            time - .00001,
            .2,
          ).distanceTo(playBallPosition(time + .00001, .2)),
          lessThan(.1),
        );
      }
      for (var i = 0; i <= 100; i++) {
        final p = playBallPosition(i / 100, .2);
        expect(p.y + 20, lessThanOrEqualTo(260));
        expect(p.x + 20, lessThan(360));
      }
    },
  );
}
