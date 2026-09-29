import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Shared room synchronizes and disposes the runtime audio bridge', () {
    final source = File('lib/shared_room.dart').readAsStringSync();

    expect(source, contains("_call('setSoundEnabled', widget.soundEnabled)"));
    expect(
      source,
      contains("_call('setGraphicsQuality', widget.graphicsQuality)"),
    );
    expect(source, contains("_call('playAudioCue', cue)"));
    expect(source, contains("_call('disposeAudio', null)"));
    final disposal = source.substring(
      source.indexOf('Future<void> _disposeResources'),
    );
    expect(
      disposal.indexOf("_call('disposeAudio', null)"),
      lessThan(disposal.indexOf('await _server.close()')),
    );
    for (final cue in [
      'uiTap',
      'uiBack',
      'uiConfirm',
      'uiReward',
      'coinSave',
      'clothFold',
      'clothPlace',
      'dishPlace',
      'boxLid',
      'boxPop',
      'waterRinse',
      'broomSweep',
    ]) {
      expect(source, contains("'$cue'"));
    }
  });
}
