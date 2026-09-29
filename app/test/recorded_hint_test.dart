import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/recorded_hint.dart';
import 'package:kopilych/ui.dart';

class _FakePlayback implements RecordedHintPlayback {
  final completed = StreamController<void>.broadcast();
  Completer<void>? pendingPlay;
  int plays = 0, stops = 0, disposals = 0;
  String? asset;

  @override
  Stream<void> get onComplete => completed.stream;

  @override
  Future<void> play(String assetPath) {
    plays++;
    asset = assetPath;
    return pendingPlay?.future ?? Future<void>.value();
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await completed.close();
  }
}

void main() {
  const text =
      'На новоселье хочется позвать друзей. Сначала устроим жизнь дома, а потом выберем мечту.';
  const asset = 'voice/elevenlabs-dylan/chapter_01.line_02.mp3';

  testWidgets('Recorded hint is manual and stops when app enters background', (
    tester,
  ) async {
    final playback = _FakePlayback();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordedHint(text: text, assetPath: asset, playback: playback),
        ),
      ),
    );

    expect(find.text(text), findsOneWidget);
    expect(playback.plays, 0, reason: 'the recording must never autoplay');
    await tester.tap(find.byKey(const ValueKey('recorded-hint-toggle')));
    await tester.pump();
    expect(playback.plays, 1);
    expect(playback.asset, asset);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CozyIcon && widget.icon == Icons.stop_rounded,
      ),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(playback.stops, 1);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CozyIcon && widget.icon == Icons.volume_up_rounded,
      ),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(playback.disposals, 1);
  });

  testWidgets('Late play completion after dispose is stopped safely', (
    tester,
  ) async {
    final playback = _FakePlayback()..pendingPlay = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordedHint(text: text, assetPath: asset, playback: playback),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('recorded-hint-toggle')));
    await tester.pump();
    expect(playback.plays, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    playback.pendingPlay!.complete();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(playback.stops, greaterThanOrEqualTo(1));
    expect(playback.disposals, 1);
    expect(tester.takeException(), isNull);
  });
}
