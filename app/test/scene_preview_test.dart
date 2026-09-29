import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/scene_preview_page.dart';

void main() {
  test(
    'Try-on keeps species, coat and growth without changing ownership or money',
    () {
      final state = GameState()
        ..species = 2
        ..color = 2
        ..achievedStage = 3
        ..equippedWearable = 'cap';
      state.purchased.add('cap');
      final before = jsonEncode(state.toJson());
      final scene = previewSceneState(state, itemId: 'bow');
      expect(scene['species'], 'hamster');
      expect(scene['color'], 'fur_03');
      expect(scene['stage'], 3);
      expect(scene['wearable'], 'bow');
      expect(scene['purchased'], containsAll(['cap', 'bow']));
      expect(scene['jobsAllowed'], false);
      expect(jsonEncode(state.toJson()), before);
      (scene['purchased'] as List).clear();
      expect(state.purchased, contains('cap'));
      expect(state.purchased, isNot(contains('bow')));
    },
  );

  test('Taking a wearable off in preview does not change the saved outfit', () {
    final state = GameState()..equippedWearable = 'bow';
    final scene = previewSceneState(state, itemId: 'bow', removeWearable: true);
    expect(scene['wearable'], isNull);
    expect(state.equippedWearable, 'bow');
  });

  test(
    'Goal previews preserve the selected goal and savings, with garden on the kitchen sill',
    () {
      final state = GameState()..goalId = 'house';
      state.wallet[1] = 150;
      final before = jsonEncode(state.toJson());
      for (final goal in ['house', 'garden', 'stars']) {
        final scene = previewSceneState(state, goalId: goal);
        expect(scene['owned'], contains(goal));
        expect(scene['room'], goal == 'garden' ? 'kitchen' : 'living');
        expect(scene['lampOn'], goal != 'stars');
        expect(jsonEncode(state.toJson()), before);
      }
    },
  );
}
