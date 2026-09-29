import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/music.dart';

class _FakeMusic implements MusicPlayback {
  final events = <String>[];

  @override
  Future<void> start(double volume) async => events.add('start:$volume');

  @override
  Future<void> resume() async => events.add('resume');

  @override
  Future<void> pause() async => events.add('pause');

  @override
  Future<void> setVolume(double volume) async => events.add('volume:$volume');

  @override
  Future<void> dispose() async => events.add('dispose');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('licensed home loop is included in the Flutter asset bundle', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains(homeMusicAsset));
  });

  test('missing licensed track stays silent', () async {
    final playback = _FakeMusic();
    final music = HomeMusic(playback: playback, hasTrack: () async => false);
    await music.configure(
      enabled: true,
      volume: 35,
      homeVisible: true,
      minigameActive: false,
    );
    expect(playback.events, isEmpty);
    await music.dispose();
    expect(playback.events, ['dispose']);
  });

  test(
    'home loop pauses in minigame/background and has its own volume',
    () async {
      final playback = _FakeMusic();
      final music = HomeMusic(playback: playback, hasTrack: () async => true);
      Future<void> configure({
        bool enabled = true,
        int volume = 35,
        bool homeVisible = true,
        bool minigameActive = false,
      }) => music.configure(
        enabled: enabled,
        volume: volume,
        homeVisible: homeVisible,
        minigameActive: minigameActive,
      );

      await configure();
      expect(playback.events.length, 1);
      expect(
        double.parse(playback.events.single.split(':').last),
        closeTo(0.07, 1e-9),
      );
      await configure(minigameActive: true);
      expect(playback.events.last, 'pause');
      await configure(volume: 70, minigameActive: true);
      expect(playback.events.last, 'pause');
      await configure(volume: 70, minigameActive: true);
      expect(playback.events.last, 'pause');
      await configure(volume: 70, minigameActive: false);
      expect(playback.events.last, 'resume');
      expect(
        double.parse(
          playback.events[playback.events.length - 2].split(':').last,
        ),
        closeTo(0.14, 1e-9),
      );
      music.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(playback.events.last, 'pause');
      music.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(playback.events.last, 'resume');
      await configure(enabled: false);
      expect(playback.events.last, 'pause');
      await music.dispose();
      expect(playback.events.last, 'dispose');
    },
  );
}
