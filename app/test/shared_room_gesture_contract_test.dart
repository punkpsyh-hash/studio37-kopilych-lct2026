import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebView claims drags while either scene minigame is active', () {
    final source = File('lib/shared_room.dart').readAsStringSync();
    final recognizers = source.substring(source.indexOf('final recognizers ='));

    expect(recognizers, contains('dish.active || job.active'));
    expect(recognizers, contains('EagerGestureRecognizer()'));
    expect(recognizers, contains('TapGestureRecognizer()'));
  });
}
