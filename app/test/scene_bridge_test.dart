import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/scene_bridge.dart';

void main() {
  test('Dish income requires a completed round and its game period', () {
    final action = <String, dynamic>{
      'type': 'action',
      'id': 'dish:1',
      'action': 'wash_dishes',
      'room': 'kitchen',
      'jobPeriod': 2,
      'proof': {'cleaned': 6, 'rinsed': true, 'waterOff': true},
    };
    expect(SceneAction.parse(action)!.jobPeriod, 2);
    expect(SceneAction.parse(action)!.isAllowedIn('kitchen'), isTrue);
    expect(SceneAction.parse(action)!.isAllowedIn('bathroom'), isFalse);
    for (final invalid in [
      {...action, 'jobPeriod': null},
      {...action, 'jobPeriod': 0},
      {...action, 'jobPeriod': '2'},
      {...action, 'proof': null},
      {
        ...action,
        'proof': {'cleaned': 5, 'rinsed': true, 'waterOff': true},
      },
      {
        ...action,
        'proof': {'cleaned': 6, 'rinsed': false, 'waterOff': true},
      },
      {
        ...action,
        'proof': {'cleaned': 6, 'rinsed': true, 'waterOff': false},
      },
    ]) {
      expect(SceneAction.parse(invalid), isNull);
    }
  });

  test('Dish progress rejects malformed counters and unknown stages', () {
    final progress = <String, dynamic>{
      'type': 'minigame',
      'game': 'dishes',
      'stage': 'scrub',
      'cleaned': 3,
      'total': 6,
      'waterOn': false,
    };
    expect(DishProgress.parse(progress)!.active, isTrue);
    expect(DishProgress.parse(progress)!.cleaned, 3);
    final covered = DishProgress.parse({
      ...progress,
      'coverage': {
        'spots': [1, .8, .7, .4, 0, 0],
        'foam': .36,
        'rinse': 0,
      },
    })!;
    expect(covered.coverage?.spots, [1, .8, .7, .4, 0, 0]);
    expect(covered.coverage?.remainingSpots, 3);
    expect(covered.coverage?.foam, .36);
    expect(covered.coverage?.rinse, 0);
    expect(
      DishProgress.parse({
        ...progress,
        'coverage': {
          'spots': [2],
        },
      })!.coverage,
      isNull,
      reason: 'Malformed optional VFX detail must not discard valid progress',
    );
    expect(
      DishProgress.parse({
        ...progress,
        'coverage': {
          'spots': [1, .8, .4, 0, 0, 0],
          'foam': .36,
          'rinse': 0,
        },
      })!.coverage,
      isNull,
      reason: 'Optional coverage must agree with the canonical cleaned count',
    );
    for (final invalid in [
      {...progress, 'cleaned': -1},
      {...progress, 'cleaned': 7},
      {...progress, 'cleaned': '3'},
      {...progress, 'waterOn': 1},
      {...progress, 'total': 10},
      {...progress, 'stage': 'reward'},
    ]) {
      expect(DishProgress.parse(invalid), isNull);
    }
    expect(readSceneMessage('{"type":"minigame"}'), isNull);
  });

  test('Progress feedback is bounded and never invalidates valid progress', () {
    final dish = <String, dynamic>{
      'type': 'minigame',
      'game': 'dishes',
      'stage': 'scrub',
      'cleaned': 1,
      'total': 6,
      'waterOn': false,
      'feedback': 'drag_required',
      'message': 'Проведи губкой по пятну.',
    };
    expect(DishProgress.parse(dish)!.feedbackCode, 'drag_required');
    expect(
      DishProgress.parse(dish)!.feedbackMessage,
      'Проведи губкой по пятну.',
    );
    expect(
      DishProgress.parse({...dish, 'feedback': 'unknown'})!.feedbackMessage,
      isNull,
    );
    expect(
      DishProgress.parse({
        ...dish,
        'message': List.filled(121, 'x').join(),
      })!.feedbackMessage,
      isNull,
    );

    final job = <String, dynamic>{
      'type': 'minigame',
      'game': 'household_job',
      'jobId': 'J02',
      'title': 'Всё на месте',
      'room': 'living',
      'stage': 'active',
      'completed': 0,
      'total': 3,
      'nextStep': 'sort',
      'feedback': 'select_target',
      'message': 'Теперь выбери подходящее место.',
    };
    expect(JobProgress.parse(job)!.feedbackCode, 'select_target');
    expect(
      JobProgress.parse({
        ...job,
        'completed': 2,
        'placedIds': ['teddy_toy', 'single_book_2'],
      })?.nextStep,
      'sort',
      reason: 'J02 may report free placement order without weakening steps',
    );
    expect(
      JobProgress.parse(job)!.feedbackMessage,
      'Теперь выбери подходящее место.',
    );
    expect(JobProgress.parse({...job, 'message': 'Плохо\n'}), isNotNull);
    expect(
      JobProgress.parse({...job, 'message': 'Плохо\n'})!.feedbackMessage,
      isNull,
    );
  });

  test('Canonical job completion requires exact room and ordered proof', () {
    final action = <String, dynamic>{
      'type': 'action',
      'id': 'job:4',
      'action': 'complete_job',
      'room': 'living',
      'jobId': 'J06',
      'jobPeriod': 4,
      'proof': {
        'completed': 6,
        'total': 6,
        'steps': ['sweep', 'sweep', 'sweep', 'empty', 'put_away', 'put_away'],
      },
    };
    final parsed = SceneAction.parse(action)!;
    expect(parsed.jobId, 'J06');
    expect(parsed.jobPeriod, 4);
    expect(parsed.isAllowedIn('living'), isTrue);
    for (final invalid in [
      {...action, 'room': 'kitchen'},
      {...action, 'jobId': 'J99'},
      {...action, 'jobPeriod': 0},
      {
        ...action,
        'proof': {
          'completed': 6,
          'total': 6,
          'steps': ['sweep', 'sweep', 'empty', 'sweep', 'put_away', 'put_away'],
        },
      },
    ]) {
      expect(SceneAction.parse(invalid), isNull);
    }
  });

  test('Generic job progress rejects forged counters and steps', () {
    final progress = <String, dynamic>{
      'type': 'minigame',
      'game': 'household_job',
      'jobId': 'J03',
      'title': 'Полотенца по местам',
      'room': 'bathroom',
      'stage': 'active',
      'completed': 2,
      'total': 4,
      'nextStep': 'shelf',
    };
    expect(JobProgress.parse(progress)!.nextStep, 'shelf');
    for (final invalid in [
      {...progress, 'room': 'living'},
      {...progress, 'completed': 5},
      {...progress, 'total': 5},
      {...progress, 'nextStep': 'fold'},
    ]) {
      expect(JobProgress.parse(invalid), isNull);
    }
  });

  test('Canonical idle event clears a completed generic round', () {
    final idle = JobProgress.parse({
      'type': 'minigame',
      'game': 'household_job',
      'jobId': 'J06',
      'title': 'Подметём вместе',
      'room': 'living',
      'stage': 'idle',
      'completed': 0,
      'total': 6,
      'nextStep': 'sweep',
    });
    expect(idle, isNotNull);
    expect(idle!.active, isFalse);
    expect(idle.nextStep, 'sweep');
  });

  test('Only room-appropriate intents cross the scene bridge', () {
    final feed = SceneAction.parse({
      'type': 'action',
      'id': 'scene_01:2',
      'action': 'feed',
      'room': 'kitchen',
    })!;
    expect(feed.isAllowedIn('kitchen'), isTrue);
    expect(feed.isAllowedIn('living'), isFalse);
    expect(
      SceneAction.parse({
        'type': 'action',
        'id': 'scene_01:water',
        'action': 'water',
        'room': 'kitchen',
      }),
      isNull,
      reason: 'The separate drinking action is no longer exposed',
    );
    for (final fixture in ['stars', 'nightlight']) {
      final action = SceneAction.parse({
        'type': 'action',
        'id': 'scene_01:$fixture',
        'action': fixture,
        'room': 'living',
      })!;
      expect(action.isAllowedIn('living'), isTrue);
      expect(action.isAllowedIn('kitchen'), isFalse);
    }
    final wrongRoom = SceneAction.parse({
      'type': 'action',
      'id': 'scene_01:3',
      'action': 'clean',
      'room': 'kitchen',
    })!;
    expect(wrongRoom.isAllowedIn('kitchen'), isFalse);
    for (final room in ['living', 'kitchen', 'bathroom']) {
      expect(
        SceneAction.parse({
          'type': 'action',
          'id': 'scene_01:lamp:$room',
          'action': 'lamp',
          'room': room,
        }),
        isNull,
        reason: 'The separate main light action is no longer exposed',
      );
    }
    expect(
      SceneAction.parse({
        'type': 'action',
        'id': 'scene_01:4',
        'action': 'room',
        'room': 'living',
        'targetRoom': 'shop',
      }),
      isNull,
    );
    expect(
      SceneAction.parse({
        'type': 'action',
        'id': "x');unsafe()",
        'action': 'lamp',
        'room': 'living',
      }),
      isNull,
    );
  });

  test('Malformed and oversized messages cannot invoke the callback', () {
    expect(readSceneMessage('not json'), isNull);
    expect(readSceneMessage('[]'), isNull);
    expect(readSceneMessage(' ' * 16001), isNull);
    expect(readSceneMessage('{"type":"ready"}'), isNull);
    expect(
      readSceneMessage('{"type":"ready","room":42,"mode":"home"}'),
      isNull,
    );
    expect(
      readSceneMessage('{"type":"ready","room":"living","mode":false}'),
      isNull,
    );
    expect(
      readSceneMessage('{"type":"diagnostic","code":"SCENE_READY","room":[]}'),
      isNull,
    );
    expect(
      readSceneMessage(
        '{"type":"diagnostic","code":"ACTION_CONTACT_COMPLETE","action":12}',
      ),
      isNull,
    );
    expect(
      readSceneMessage(
        '{"type":"ready","room":"living","mode":"home"}',
      )?['type'],
      'ready',
    );
  });
}
