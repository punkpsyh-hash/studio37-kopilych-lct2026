import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/pet_motion.dart';
import 'package:kopilych/story.dart';

void markLesson(GameState state, String id) {
  state.completed
    ..add(id)
    ..add(canonLessonMarker(id, state.day));
}

void main() {
  test('canonical five-period route survives reload and keeps exact money', () {
    final state = GameState()..name = 'Персик';
    expect(currentChapter(state), 1, reason: 'adoption finishes the prologue');

    markLesson(state, 'S01');
    state.confirmPlan([15, 10, 20]);
    markLesson(state, 'B02');
    final reward = CanonLessonSubmission.capture(
      state,
      lessonId: 'P01',
      practice: false,
      basketIds: const ['food_refill', 'clean_care'],
      rationale: 'Корм и чистота нужны питомцу сегодня',
    ).apply(state);
    expect(reward, 30);
    state.confirmPlan([15, 15, 30], reason: 'После дохода уточняю суммы');
    markLesson(state, 'B04');
    for (var kind = 0; kind < 3; kind++) {
      state.care(kind);
    }
    state.buyItem(catalogItems.firstWhere((item) => item.id == 'ball'));
    state.transfer(0, 1, 25);
    state.transfer(0, 2, 5);
    markLesson(state, 'S02');
    state.endDay(
      reviewed: true,
      explanation: 'После дохода уточнили план первого периода',
    );
    expect(state.wallet, [70, 25, 5]);

    void runWorkPeriod(
      String jobId, {
      required String room,
      bool compareGoals = false,
      bool finalPeriod = false,
    }) {
      state.confirmPlan(state.day == 3 ? [15, 10, 15] : [15, 0, 15]);
      markLesson(state, 'B02');
      state.setCurrentRoom(room);
      expect(state.finishJob(jobId, period: state.day), 30);
      state.confirmPlan(
        [15, 0, 25],
        reason: state.day == 3
            ? 'Откладываю желание и направляю деньги важнее'
            : 'После дохода уточняю суммы',
      );
      markLesson(state, 'B04');
      if (compareGoals) markLesson(state, 'S01');
      for (var kind = 0; kind < 3; kind++) {
        state.care(kind);
      }
      state.transfer(0, 1, 25);
      markLesson(state, 'S02');
      if (finalPeriod) {
        final bed = catalogItems.firstWhere((item) => item.id == 'cozy_bed');
        expect(() => state.buyItem(bed), throwsA(isA<GameRule>()));
        markLesson(state, 'P06');
        state.buyGoal();
      }
      state.endDay(
        reviewed: true,
        explanation: 'После дохода уточнили план и сохранили вклад',
      );
    }

    runWorkPeriod('J02', room: 'living');
    runWorkPeriod('J03', room: 'bathroom');
    runWorkPeriod('J04', room: 'kitchen', compareGoals: true);
    runWorkPeriod('J05', room: 'living', finalPeriod: true);

    expect(state.wallet, [30, 5, 5]);
    expect(state.owned, contains('house'));
    expect(currentChapter(state), 6);
    expect(state.stage, 3);

    final before = jsonEncode(state.toJson());
    for (var i = 0; i < 5; i++) {
      storyChapters(state);
      storyActiveTask(state);
    }
    expect(jsonEncode(state.toJson()), before);
    final reloaded = GameState.fromJson(jsonDecode(before));
    expect(reloaded.wallet, [30, 5, 5]);
    expect(reloaded.total, 40);
    expect(reloaded.stage, 3);
    expect(currentChapter(reloaded), 6);
  });

  test(
    'v2 migration preserves progress and derives only evidenced deposits',
    () {
      final old = GameState().toJson()
        ..['schema'] = 2
        ..remove('storyMarks')
        ..['wallet'] = [70, 0, 20]
        ..['owned'] = ['garden'];
      final state = GameState.fromJson(old);
      expect(state.wallet, [70, 0, 20]);
      expect(state.storyMarks, {'saved', 'reserve'});
      expect(GameState.fromJson(state.toJson()).storyMarks, state.storyMarks);
      final empty = GameState().toJson()
        ..['schema'] = 2
        ..remove('storyMarks');
      expect(GameState.fromJson(empty).storyMarks, isEmpty);
    },
  );

  test('Invalid transfer cannot mark a story milestone', () {
    final state = GameState();
    expect(() => state.transfer(0, 2, 101), throwsA(isA<GameRule>()));
    expect(state.storyMarks, isEmpty);
    expect(state.wallet, [100, 0, 0]);
  });

  test(
    'Animation endpoints match rest and feet leave floor only in flight',
    () {
      for (final action in PetAction.values) {
        for (final t in [0.0, 1.0]) {
          final pose = samplePetMotion(action, t);
          expect(pose.y, 0);
          expect(pose.squash, 1);
          expect(pose.head, 0);
          expect(pose.left, 0);
          expect(pose.right, 0);
        }
        for (var i = 0; i <= 100; i++) {
          final pose = samplePetMotion(action, i / 100);
          expect(pose.squash, inInclusiveRange(.85, 1.08));
          expect(pose.y, inInclusiveRange(-38, 0));
          if (![PetAction.play, PetAction.celebrate].contains(action)) {
            expect(pose.y, 0);
          }
        }
      }
      expect(samplePetMotion(PetAction.play, .14).squash, lessThan(1));
      expect(samplePetMotion(PetAction.play, .42).y, lessThan(-30));
      expect(samplePetMotion(PetAction.play, .66).y, 0);
    },
  );
}
