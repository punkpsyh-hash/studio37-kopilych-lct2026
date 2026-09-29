import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const homeMusicAsset = 'assets/audio/music/home_loop.ogg';

abstract interface class MusicPlayback {
  Future<void> start(double volume);
  Future<void> resume();
  Future<void> pause();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class _AssetMusicPlayback implements MusicPlayback {
  AudioPlayer? _player;
  AudioPlayer get _activePlayer => _player ??= AudioPlayer();

  @override
  Future<void> start(double volume) async {
    final player = _activePlayer;
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(volume);
    await player.play(AssetSource('audio/music/home_loop.ogg'));
  }

  @override
  Future<void> resume() => _player?.resume() ?? Future<void>.value();

  @override
  Future<void> pause() => _player?.pause() ?? Future<void>.value();

  @override
  Future<void> setVolume(double volume) =>
      _player?.setVolume(volume) ?? Future<void>.value();

  @override
  Future<void> dispose() => _player?.dispose() ?? Future<void>.value();
}

Future<bool> _bundledHomeMusic() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return manifest.listAssets().contains(homeMusicAsset);
}

/// A single quiet home loop. No player is started until a licensed track is
/// bundled; music volume and enablement are independent of Web Audio effects.
class HomeMusic with WidgetsBindingObserver {
  HomeMusic({MusicPlayback? playback, Future<bool> Function()? hasTrack})
    : _playback = playback ?? _AssetMusicPlayback(),
      _hasTrack =
          hasTrack ??
          (Platform.environment.containsKey('FLUTTER_TEST')
              ? (() async => false)
              : _bundledHomeMusic) {
    WidgetsBinding.instance.addObserver(this);
  }

  final MusicPlayback _playback;
  final Future<bool> Function() _hasTrack;
  Future<void> _pending = Future<void>.value();
  bool _enabled = true;
  bool _homeVisible = false;
  bool _minigameActive = false;
  bool _foreground = true;
  bool _started = false;
  bool _playing = false;
  bool _unavailable = false;
  bool _disposed = false;
  int _volume = 35;

  bool get enabled => _enabled;
  int get volume => _volume;

  /// Volume 100 is capped at 20% player gain so speech remains foreground.
  double get _gain => _volume / 100 * 0.20;
  bool get _shouldPlay =>
      _enabled &&
      _volume > 0 &&
      _homeVisible &&
      !_minigameActive &&
      _foreground;

  Future<void> configure({
    required bool enabled,
    required int volume,
    required bool homeVisible,
    required bool minigameActive,
  }) {
    _enabled = enabled;
    _volume = volume.clamp(0, 100).toInt();
    _homeVisible = homeVisible;
    _minigameActive = minigameActive;
    return _queue();
  }

  Future<void> _queue() {
    if (_disposed) return Future<void>.value();
    _pending = _pending.then((_) => _apply());
    return _pending;
  }

  Future<void> _apply() async {
    if (_disposed) return;
    try {
      if (!_shouldPlay || _unavailable) {
        if (_playing) {
          await _playback.pause();
          _playing = false;
        }
        return;
      }
      if (!_started) {
        if (!await _hasTrack()) {
          _unavailable = true;
          return;
        }
        // Visibility can change while the asset manifest is loading.
        if (_disposed || !_shouldPlay) return;
        await _playback.start(_gain);
        _started = _playing = true;
      } else {
        await _playback.setVolume(_gain);
        if (!_playing) {
          await _playback.resume();
          _playing = true;
        }
      }
    } catch (_) {
      // Missing or undecodable music must not interrupt the game.
      _unavailable = true;
      _playing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_queue());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _pending;
    await _playback.dispose();
  }
}
