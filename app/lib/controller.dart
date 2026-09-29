import 'package:flutter/foundation.dart';
import 'game.dart';
import 'storage.dart';

class GameController extends ChangeNotifier {
  GameController(this.store);
  final GameStore store;
  GameState? state;
  bool busy = false;
  Object? loadError;
  int loginBonusAwarded = 0;
  int _sequence = 0;
  final _session = DateTime.now().microsecondsSinceEpoch.toString();
  Future<void> load() async {
    loadError = null;
    loginBonusAwarded = 0;
    try {
      final loaded = await store.load();
      final now = DateTime.now();
      state = loaded.needsResume(now)
          ? await store.change(
              'resume:$_session:${_sequence++}',
              'Возвращение в игру',
              (game) => game.resume(now),
            )
          : loaded;
      if (state != null && state!.wallet[0] > loaded.wallet[0]) {
        loginBonusAwarded = state!.wallet[0] - loaded.wallet[0];
      }
    } catch (e) {
      loadError = e;
    }
    notifyListeners();
  }

  Future<void> change(
    String label,
    void Function(GameState) action, {
    String? id,
  }) => _runStoreAction(
    () => store.change(id ?? '$_session:${_sequence++}', label, action),
  );

  /// The two spoken explanations in the first-day guide have stable IDs, so
  /// reopening a screen cannot advance or reward the guide twice.
  Future<void> acknowledgeIntro(String step) {
    if (step != 'money' && step != 'goal') {
      throw ArgumentError.value(step, 'step');
    }
    return change(
      'Объяснение первого дня: $step',
      (game) => game.completed.add('intro-$step'),
      id: 'intro:ack:$step',
    );
  }

  Future<void> startDemo() => _runStoreAction(store.startDemo);

  Future<void> exitDemo() => _runStoreAction(store.exitDemo);

  Future<void> resetDemo() => _runStoreAction(store.resetDemo);

  Future<void> _runStoreAction(Future<GameState> Function() action) async {
    if (busy) throw const GameRule('Сохраняем предыдущее действие.');
    busy = true;
    notifyListeners();
    try {
      state = await action();
      loadError = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
