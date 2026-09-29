import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'voice_models.dart';
export 'voice_models.dart';

/// Allows the dialogue to test its playback decisions without native audio.
abstract interface class VoiceSession implements Listenable {
  bool get listening;
  bool get busy;
  bool get speaking;
  Future<void> say(String text, {String? clipId});
  Future<void> startListening(VoidCallback onTimeLimit);
  Future<String> finishListening();
  Future<void> stop();
  void dispose();
}

/// Models ship in the APK. No network service, background listening or saved
/// transcript history. One bounded utterance is kept only until recognition.
class LocalVoice extends ChangeNotifier implements VoiceSession {
  static Future<void>? _startupCleanup;
  static Future<Map<String, dynamic>>? _recordedCatalog;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  Future<String>? _modelPath;
  Timer? _limit;
  StreamSubscription<Duration>? _position;
  StreamSubscription<void>? _completion;
  @override
  bool listening = false;
  @override
  bool busy = false;
  @override
  bool speaking = false;
  bool _closed = false;
  double mouth = 0;
  int _epoch = 0;
  String? _inputPath, _outputPath;
  List<double> _envelope = [];
  final _session = DateTime.now().microsecondsSinceEpoch;
  Future<Object?>? _nativeWork;

  LocalVoice() {
    _position = _player.onPositionChanged.listen((p) {
      if (!speaking || _envelope.isEmpty) return;
      final i = (p.inMilliseconds ~/ 80).clamp(0, _envelope.length - 1);
      mouth = _envelope[i];
      _notify();
    });
    _completion = _player.onPlayerComplete.listen((_) {
      speaking = false;
      mouth = 0;
      _notify();
    });
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<String> prepare() =>
      _modelPath ??= _copyModels().catchError((Object e) {
        _modelPath = null;
        throw e;
      });

  Future<String> _copyModels() async {
    await (_startupCleanup ??= _removeAbandonedAudio());
    final root = '${(await getApplicationSupportDirectory()).path}/voice-v1';
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = manifest.listAssets().where(
      (p) =>
          p.startsWith('assets/voice/') &&
          !p.startsWith('assets/voice/elevenlabs-dylan/'),
    );
    if (files.isEmpty) throw StateError('В сборке нет голосовых моделей.');
    for (final asset in files) {
      final target = File('$root/${asset.substring('assets/voice/'.length)}');
      if (await target.exists()) continue;
      final bytes = await rootBundle.load(asset);
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.part');
      await temporary.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await temporary.rename(target.path);
    }
    return root;
  }

  static Future<void> _removeAbandonedAudio() async {
    // First voice session in this process: no recording can yet be active.
    // Remove our temporary files left by an interrupted previous process.
    final cache = await getTemporaryDirectory();
    await for (final entry in cache.list()) {
      if (entry is File &&
          (entry.uri.pathSegments.last.startsWith('pet-input-') ||
              entry.uri.pathSegments.last.startsWith('pet-speech-'))) {
        await _delete(entry.path);
      }
    }
  }

  Future<List<double>?> _recordedEnvelope(String clipId, String text) async {
    try {
      final catalog = await (_recordedCatalog ??= rootBundle
          .loadString('assets/voice/elevenlabs-dylan/catalog.json')
          .then((value) => jsonDecode(value) as Map<String, dynamic>));
      final clips = catalog['clips'] as Map<String, dynamic>;
      final clip = clips[clipId] as Map<String, dynamic>?;
      if (clip?['text'] != text) return null;
      return (clip!['envelope'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList();
    } catch (_) {
      // The bundled voice is optional; the offline synthesizer remains usable.
      return null;
    }
  }

  @override
  Future<void> say(String text, {String? clipId}) async {
    if (_closed || busy || listening || text.trim().isEmpty) return;
    await stop();
    final epoch = _epoch;
    busy = true;
    _notify();
    String? output;
    try {
      if (clipId != null) {
        final recorded = await _recordedEnvelope(clipId, text);
        if (_closed || epoch != _epoch) return;
        if (recorded != null) {
          _envelope = recorded;
          await _player.play(AssetSource('voice/elevenlabs-dylan/$clipId.mp3'));
          if (_closed || epoch != _epoch) {
            await _player.stop();
            return;
          }
          speaking = true;
          return;
        }
      }
      final root = await prepare();
      await _waitForNative();
      if (_closed || epoch != _epoch) return;
      output =
          '${(await getTemporaryDirectory()).path}/pet-speech-$_session-$epoch.wav';
      _outputPath = output;
      final job = synthesizeSpeech(root, text, output);
      _nativeWork = job;
      final envelope = await job;
      if (_closed || epoch != _epoch) {
        await _delete(output);
        return;
      }
      _envelope = envelope;
      await _player.play(DeviceFileSource(output));
      if (_closed || epoch != _epoch) {
        await _player.stop();
        return;
      }
      speaking = true;
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        speaking = false;
        mouth = 0;
      }
      rethrow;
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  Future<void> startListening(VoidCallback onTimeLimit) async {
    if (_closed || busy || listening) return;
    await stop();
    final epoch = _epoch;
    busy = true;
    _notify();
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Микрофон не разрешён. Можно отвечать кнопками.');
      }
      await prepare();
      if (_closed || epoch != _epoch) return;
      _inputPath =
          '${(await getTemporaryDirectory()).path}/pet-input-$_session-$epoch.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _inputPath!,
      );
      if (_closed || epoch != _epoch) {
        await _recorder.cancel();
        return;
      }
      listening = true;
      _limit = Timer(const Duration(seconds: 12), onTimeLimit);
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  Future<String> finishListening() async {
    if (!listening || _closed) return '';
    _limit?.cancel();
    listening = false;
    busy = true;
    final epoch = _epoch;
    _notify();
    String? input = _inputPath;
    // This operation owns the file until decoding finishes. A concurrent
    // stop/dispose must not unlink it while the native worker opens it.
    _inputPath = null;
    try {
      input = await _recorder.stop() ?? input;
      if (input == null) return '';
      final root = await prepare();
      await _waitForNative();
      if (_closed || epoch != _epoch) return '';
      final job = recognizeSpeech(root, input);
      _nativeWork = job;
      final text = await job;
      return !_closed && epoch == _epoch ? text : '';
    } finally {
      await _delete(input);
      if (_inputPath == input) _inputPath = null;
      if (!_closed && epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  Future<void> stop() async {
    _epoch++;
    _limit?.cancel();
    final wasSpeaking = speaking;
    if (listening) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // A lost native recorder must not block text navigation.
      }
    }
    listening = speaking = busy = false;
    mouth = 0;
    if (wasSpeaking) {
      try {
        await _player.stop();
      } catch (_) {
        // Audio may be unavailable after route or app lifecycle changes.
      }
    }
    await _delete(_inputPath);
    await _delete(_outputPath);
    _inputPath = _outputPath = null;
    _notify();
  }

  static Future<void> _delete(String? path) async {
    if (path != null) {
      final f = File(path);
      try {
        await f.delete();
      } on FileSystemException {
        if (await f.exists()) rethrow;
      }
    }
  }

  Future<void> _waitForNative() async {
    try {
      await _nativeWork;
    } catch (_) {
      /* The requesting UI handles errors. */
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _limit?.cancel();
    _position?.cancel();
    _completion?.cancel();
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    try {
      await _recorder.dispose();
    } catch (_) {
      // A missing native plugin has no recording resources to release.
    }
    try {
      await _player.dispose();
    } catch (_) {
      // A missing native plugin has no playback resources to release.
    }
    await _delete(_inputPath);
    await _delete(_outputPath);
  }
}
