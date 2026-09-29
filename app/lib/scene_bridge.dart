import 'dart:convert';

const sceneRooms = {'living', 'kitchen', 'bathroom'};
const sceneJobRooms = <String, String>{
  'J01': 'kitchen',
  'J02': 'living',
  'J03': 'bathroom',
  'J04': 'kitchen',
  'J05': 'living',
  'J06': 'living',
};
const sceneJobSteps = <String, List<String>>{
  'J01': [
    'scrub',
    'scrub',
    'scrub',
    'scrub',
    'scrub',
    'scrub',
    'rinse',
    'water_off',
  ],
  'J02': ['sort', 'sort', 'sort'],
  'J03': ['fold', 'fold', 'shelf', 'shelf'],
  'J04': ['sort', 'sort', 'sort', 'sort'],
  'J05': ['wipe', 'wipe', 'wipe', 'put_away'],
  'J06': ['sweep', 'sweep', 'sweep', 'empty', 'put_away', 'put_away'],
};
const sceneFeedbackCodes = {
  'wrong_source',
  'wrong_target',
  'drag_required',
  'select_target',
};

({String code, String message})? _readProgressFeedback(
  Map<String, dynamic> message,
) {
  final code = message['feedback'];
  final text = message['message'];
  if (code is! String || !sceneFeedbackCodes.contains(code)) return null;
  if (text is! String) return null;
  final clean = text.trim();
  if (clean.isEmpty ||
      clean.length > 120 ||
      RegExp(r'[\u0000-\u001F\u007F]').hasMatch(text)) {
    return null;
  }
  return (code: code, message: clean);
}

/// The scene can request actions; it cannot submit prices or wallet balances.
class SceneAction {
  const SceneAction(
    this.id,
    this.action,
    this.room,
    this.targetRoom, {
    this.jobPeriod,
    this.jobId,
  });
  final String id, action, room;
  final String? targetRoom;
  final int? jobPeriod;
  final String? jobId;

  static SceneAction? parse(Map<String, dynamic> message) {
    final id = message['id'];
    final action = message['action'];
    final room = message['room'];
    final target = message['targetRoom'];
    if (message['type'] != 'action' ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9:_-]{1,128}$').hasMatch(id) ||
        !{
          'feed',
          'play',
          'clean',
          'stars',
          'nightlight',
          'room',
          'wash_dishes',
          'complete_job',
        }.contains(action) ||
        !sceneRooms.contains(room) ||
        (action == 'room' && !sceneRooms.contains(target)) ||
        (action != 'room' && target != null)) {
      return null;
    }
    if (action == 'complete_job') {
      final period = message['jobPeriod'];
      final jobId = message['jobId'];
      final proof = message['proof'];
      final expected = sceneJobSteps[jobId];
      if (period is! int ||
          period < 1 ||
          jobId is! String ||
          sceneJobRooms[jobId] != room ||
          proof is! Map ||
          proof['completed'] != expected?.length ||
          proof['total'] != expected?.length ||
          proof['steps'] is! List ||
          !_sameStrings(proof['steps'] as List, expected!)) {
        return null;
      }
      return SceneAction(
        id,
        action as String,
        room as String,
        null,
        jobPeriod: period,
        jobId: jobId,
      );
    }
    if (action == 'wash_dishes') {
      final period = message['jobPeriod'];
      final proof = message['proof'];
      if (period is! int ||
          period < 1 ||
          proof is! Map ||
          proof['cleaned'] != 6 ||
          proof['rinsed'] != true ||
          proof['waterOff'] != true) {
        return null;
      }
      return SceneAction(
        id,
        action as String,
        room as String,
        null,
        jobPeriod: period,
      );
    }
    return SceneAction(id, action as String, room as String, target as String?);
  }

  bool isAllowedIn(String currentRoom) =>
      room == currentRoom &&
      switch (action) {
        'feed' || 'wash_dishes' => room == 'kitchen',
        'complete_job' => sceneJobRooms[jobId] == room,
        'clean' => room == 'bathroom',
        'play' || 'stars' || 'nightlight' => room == 'living',
        'room' => targetRoom != room,
        _ => false,
      };
}

bool _sameStrings(List<dynamic> actual, List<String> expected) =>
    actual.length == expected.length &&
    Iterable<int>.generate(
      expected.length,
    ).every((index) => actual[index] == expected[index]);

class JobPlacementOption {
  const JobPlacementOption(this.id, this.label);
  final String id, label;

  static List<JobPlacementOption>? parseList(Object? value) {
    if (value is! List || value.length > 4) return null;
    final result = <JobPlacementOption>[];
    final ids = <String>{};
    for (final option in value) {
      if (option is! Map ||
          option['id'] is! String ||
          option['label'] is! String) {
        return null;
      }
      final id = option['id'] as String;
      final label = option['label'] as String;
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(id) ||
          label.trim().isEmpty ||
          label.length > 60 ||
          !ids.add(id)) {
        return null;
      }
      result.add(JobPlacementOption(id, label));
    }
    return List.unmodifiable(result);
  }
}

class JobProgress {
  const JobProgress({
    this.jobId = '',
    this.title = '',
    this.room = '',
    this.stage = 'idle',
    this.completed = 0,
    this.total = 0,
    this.nextStep,
    this.feedbackCode,
    this.feedbackMessage,
    this.placementSources = const [],
    this.placementTargets = const [],
    this.placementBusy = false,
  });
  final String jobId, title, room, stage;
  final int completed, total;
  final String? nextStep;
  final String? feedbackCode, feedbackMessage;
  final List<JobPlacementOption> placementSources, placementTargets;
  final bool placementBusy;
  bool get active => stage != 'idle';

  static JobProgress? parse(Map<String, dynamic> message) {
    if (message['type'] != 'minigame' ||
        message['game'] != 'household_job' ||
        message['jobId'] is! String ||
        message['title'] is! String ||
        message['room'] is! String ||
        !{
          'idle',
          'active',
          'ready',
          'awaiting_ack',
        }.contains(message['stage']) ||
        message['completed'] is! int ||
        message['total'] is! int ||
        (message['nextStep'] != null && message['nextStep'] is! String)) {
      return null;
    }
    final jobId = message['jobId'] as String;
    final expected = sceneJobSteps[jobId];
    final completed = message['completed'] as int;
    if (expected == null ||
        sceneJobRooms[jobId] != message['room'] ||
        message['total'] != expected.length ||
        completed < 0 ||
        completed > expected.length ||
        (completed < expected.length &&
            message['nextStep'] != expected[completed]) ||
        (completed == expected.length && message['nextStep'] != null)) {
      return null;
    }
    final feedback = _readProgressFeedback(message);
    final placement = message['placement'];
    List<JobPlacementOption> sources = const [], targets = const [];
    var placementBusy = false;
    if (placement != null) {
      if (!{'J02', 'J04'}.contains(jobId) ||
          placement is! Map ||
          placement['busy'] is! bool) {
        return null;
      }
      final parsedSources = JobPlacementOption.parseList(placement['sources']);
      final parsedTargets = JobPlacementOption.parseList(placement['targets']);
      if (parsedSources == null || parsedTargets == null) return null;
      sources = parsedSources;
      targets = parsedTargets;
      placementBusy = placement['busy'] as bool;
    }
    return JobProgress(
      jobId: jobId,
      title: message['title'] as String,
      room: message['room'] as String,
      stage: message['stage'] as String,
      completed: completed,
      total: expected.length,
      nextStep: message['nextStep'] as String?,
      feedbackCode: feedback?.code,
      feedbackMessage: feedback?.message,
      placementSources: sources,
      placementTargets: targets,
      placementBusy: placementBusy,
    );
  }
}

class DishProgress {
  const DishProgress({
    this.stage = 'idle',
    this.cleaned = 0,
    this.waterOn = false,
    this.feedbackCode,
    this.feedbackMessage,
    this.coverage,
  });
  final String stage;
  final int cleaned;
  final bool waterOn;
  final String? feedbackCode, feedbackMessage;
  final DishCoverage? coverage;
  bool get active => stage != 'idle';
  static DishProgress? parse(Map<String, dynamic> message) {
    if (message['type'] != 'minigame' ||
        message['game'] != 'dishes' ||
        !{
          'idle',
          'scrub',
          'rinse',
          'water_off',
          'awaiting_ack',
        }.contains(message['stage']) ||
        message['cleaned'] is! int ||
        message['cleaned'] < 0 ||
        message['cleaned'] > 6 ||
        message['total'] != 6 ||
        message['waterOn'] is! bool) {
      return null;
    }
    final feedback = _readProgressFeedback(message);
    final parsedCoverage = DishCoverage.tryParse(message['coverage']);
    final coverage =
        parsedCoverage != null &&
            parsedCoverage.completedSpots == message['cleaned']
        ? parsedCoverage
        : null;
    return DishProgress(
      stage: message['stage'] as String,
      cleaned: message['cleaned'] as int,
      waterOn: message['waterOn'] as bool,
      feedbackCode: feedback?.code,
      feedbackMessage: feedback?.message,
      coverage: coverage,
    );
  }
}

class DishCoverage {
  static const completionThreshold = .68;

  const DishCoverage({
    required this.spots,
    required this.foam,
    required this.rinse,
  });

  final List<double> spots;
  final double foam, rinse;

  int get completedSpots => spots.length - remainingSpots;

  int get remainingSpots =>
      spots.where((value) => value < completionThreshold).length;

  static DishCoverage? tryParse(Object? value) {
    if (value is! Map || value['spots'] is! List) return null;
    final rawSpots = value['spots'] as List;
    final foam = _unitValue(value['foam']);
    final rinse = _unitValue(value['rinse']);
    if (rawSpots.length != 6 || foam == null || rinse == null) return null;
    final spots = rawSpots.map(_unitValue).toList();
    if (spots.any((spot) => spot == null)) return null;
    return DishCoverage(
      spots: List<double>.unmodifiable(spots.cast<double>()),
      foam: foam,
      rinse: rinse,
    );
  }

  static double? _unitValue(Object? value) {
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      return null;
    }
    return value.toDouble();
  }
}

class SceneActionResult {
  const SceneActionResult(this.accepted, {this.message, this.state});
  final bool accepted;
  final String? message;
  final Map<String, Object?>? state;

  Map<String, Object?> acknowledgement(String id) => {
    'id': id,
    'accepted': accepted,
    if (message != null) 'message': message,
    if (state != null) 'state': state,
  };
}

Map<String, dynamic>? readSceneMessage(String value) {
  if (value.length > 16000) return null;
  try {
    final message = jsonDecode(value);
    if (message is! Map<String, dynamic>) return null;
    final type = message['type'];
    if (!{
      'ready',
      'diagnostic',
      'error',
      'action',
      'minigame',
    }.contains(type)) {
      return null;
    }
    if (type == 'minigame' &&
        DishProgress.parse(message) == null &&
        JobProgress.parse(message) == null) {
      return null;
    }
    if (type == 'ready' &&
        (!sceneRooms.contains(message['room']) ||
            !{'home', 'adoption'}.contains(message['mode']))) {
      return null;
    }
    if (type == 'diagnostic') {
      if (message['code'] is! String ||
          (message['room'] != null && !sceneRooms.contains(message['room'])) ||
          (message['action'] != null && message['action'] is! String)) {
        return null;
      }
      if (message['code'] == 'SCENE_READY' &&
          (!sceneRooms.contains(message['room']) ||
              !{'home', 'adoption'}.contains(message['mode']))) {
        return null;
      }
      if (message['code'] == 'ACTION_CONTACT_COMPLETE' &&
          !{
            'feed',
            'play',
            'clean',
            'stars',
            'nightlight',
            'room',
            'wash_dishes',
            'complete_job',
          }.contains(message['action'])) {
        return null;
      }
    }
    return message;
  } on FormatException {
    return null;
  }
}
