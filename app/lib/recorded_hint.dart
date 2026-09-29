import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'ui.dart';

abstract interface class RecordedHintPlayback {
  Stream<void> get onComplete;

  Future<void> play(String assetPath);

  Future<void> stop();

  Future<void> dispose();
}

class _AssetRecordedHintPlayback implements RecordedHintPlayback {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(String assetPath) => _player.play(AssetSource(assetPath));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// A visible hint with optional, user-initiated playback of a bundled recording.
class RecordedHint extends StatefulWidget {
  const RecordedHint({
    super.key,
    required this.text,
    required this.assetPath,
    this.playback,
  });

  final String text;
  final String assetPath;

  /// Injectable for deterministic lifecycle tests. Production uses AudioPlayer.
  final RecordedHintPlayback? playback;

  @override
  State<RecordedHint> createState() => _RecordedHintState();
}

class _RecordedHintState extends State<RecordedHint>
    with WidgetsBindingObserver {
  late final RecordedHintPlayback _playback;
  StreamSubscription<void>? _completion;
  bool _playing = false, _starting = false, _failed = false, _closed = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback = widget.playback ?? _AssetRecordedHintPlayback();
    _completion = _playback.onComplete.listen((_) {
      if (_closed || !_playing || !mounted) return;
      _epoch++;
      setState(() {
        _playing = false;
        _starting = false;
      });
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _stop();
      return;
    }
    if (_starting || _closed) return;
    final epoch = ++_epoch;
    setState(() {
      _playing = true;
      _starting = true;
      _failed = false;
    });
    try {
      await _playback.play(widget.assetPath);
      if (_closed || !mounted || epoch != _epoch) {
        await _safeStop();
        return;
      }
      setState(() => _starting = false);
    } catch (_) {
      if (!_closed && mounted && epoch == _epoch) {
        setState(() {
          _playing = false;
          _starting = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _stop() async {
    _epoch++;
    if (!_closed && mounted) {
      setState(() {
        _playing = false;
        _starting = false;
      });
    }
    await _safeStop();
  }

  Future<void> _safeStop() async {
    try {
      await _playback.stop();
    } catch (_) {
      // A platform player may already be stopping or disposed.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_completion?.cancel());
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    await _safeStop();
    try {
      await _playback.dispose();
    } catch (_) {
      // Disposal is best-effort after the widget leaves the tree.
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.text)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('recorded-hint-toggle'),
                onPressed: _toggle,
                tooltip: _playing ? 'Остановить реплику' : 'Прослушать реплику',
                icon: CozyIcon(
                  _playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                ),
              ),
            ],
          ),
          if (_failed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Запись не включилась. Реплику можно прочитать на экране.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
}
