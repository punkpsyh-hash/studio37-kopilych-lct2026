import 'dart:math' as math;

enum PetAction { idle, feed, play, bath, love, celebrate }

/// Authored poses, in design pixels and radians. Feet stay at y=259;
/// squash is applied around the floor, never around the character centre.
class PetPose {
  const PetPose({
    this.y = 0,
    this.squash = 1,
    this.lean = 0,
    this.head = 0,
    this.nod = 0,
    this.left = 0,
    this.right = 0,
    this.tail = 0,
    this.eyes = 0,
  });
  final double y, squash, lean, head, nod, left, right, tail, eyes;
  static PetPose mix(PetPose a, PetPose b, double t) {
    double v(double x, double y) => x + (y - x) * t;
    return PetPose(
      y: v(a.y, b.y),
      squash: v(a.squash, b.squash),
      lean: v(a.lean, b.lean),
      head: v(a.head, b.head),
      nod: v(a.nod, b.nod),
      left: v(a.left, b.left),
      right: v(a.right, b.right),
      tail: v(a.tail, b.tail),
      eyes: v(a.eyes, b.eyes),
    );
  }
}

typedef PoseKey = (double, PetPose);
const _rest = PetPose();
const motionKeys = <PetAction, List<PoseKey>>{
  PetAction.feed: [
    (0, _rest),
    (.14, PetPose(head: -.10)),
    (.3, PetPose(nod: 25, head: .10, left: .12, right: -.12)),
    (.62, PetPose(nod: 25, eyes: .8, left: .12, right: -.12)),
    (.8, PetPose(nod: 4, head: -.08, eyes: 1)),
    (1, _rest),
  ],
  PetAction.play: [
    (0, _rest),
    (.14, PetPose(squash: .89, nod: 6, head: .09)),
    (.23, PetPose(y: -10, squash: 1.07, left: .25, right: -.3)),
    (
      .42,
      PetPose(
        y: -37,
        squash: 1.02,
        head: -.10,
        left: .7,
        right: -.85,
        eyes: .1,
      ),
    ),
    (.59, PetPose(y: -6, squash: 1.07, left: .4, right: -.4)),
    (.66, PetPose(squash: .86, nod: 5, eyes: 1)),
    (.79, PetPose(squash: 1.025, head: .05)),
    (1, _rest),
  ],
  PetAction.bath: [
    (0, _rest),
    (.16, PetPose(head: -.12, left: .35, right: -.35)),
    (.32, PetPose(lean: .045, head: -.13, eyes: 1, left: .6, right: -.2)),
    (.5, PetPose(lean: -.045, head: .13, eyes: 1, left: .2, right: -.6)),
    (.67, PetPose(lean: .03, head: -.08, eyes: 1, left: .5, right: -.3)),
    (.83, PetPose(head: .04, eyes: .3)),
    (1, _rest),
  ],
  PetAction.love: [
    (0, _rest),
    (.16, PetPose(squash: .96, head: -.1)),
    (.36, PetPose(squash: 1.025, head: .06, left: 1, right: -1, eyes: 1)),
    (.68, PetPose(head: -.07, left: .88, right: -.88, eyes: 1)),
    (.85, PetPose(left: .2, right: -.2)),
    (1, _rest),
  ],
  PetAction.celebrate: [
    (0, _rest),
    (.12, PetPose(squash: .88, eyes: 1)),
    (.3, PetPose(y: -29, squash: 1.04, left: 1, right: -1, eyes: 1)),
    (.48, PetPose(squash: .9, left: .5, right: -.5)),
    (.65, PetPose(y: -14, left: .8, right: -.8, eyes: 1)),
    (.8, PetPose(squash: .94)),
    (1, _rest),
  ],
};

PetPose samplePetMotion(PetAction action, double progress) {
  final keys = motionKeys[action];
  if (keys == null) return _rest;
  final t = progress.clamp(0.0, 1.0);
  for (var i = 1; i < keys.length; i++) {
    if (t <= keys[i].$1) {
      final a = keys[i - 1], b = keys[i];
      final u = (t - a.$1) / (b.$1 - a.$1);
      // Smoothstep on authored intervals, not a sine wave for the whole action.
      return PetPose.mix(a.$2, b.$2, u * u * (3 - 2 * u));
    }
  }
  return _rest;
}

double motionPresence(double t) =>
    math.min((t / .12).clamp(0.0, 1.0), ((1 - t) / .16).clamp(0.0, 1.0));

/// Ball follows the right paw through the lift, then continues independently.
/// The same shoulder, wrist and floor transforms are used by StorybookPet.
math.Point<double> playBallPosition(double progress, double phase) {
  final t = progress.clamp(0.0, 1.0);
  math.Point<double> atPaw(double time) {
    final pose = samplePetMotion(PetAction.play, time);
    final breath = 1 + math.sin(phase * math.pi * 2) * .009;
    final x =
        (32 - math.sin(pose.right) * 49) * breath / math.sqrt(pose.squash);
    final y = (-62 + math.cos(pose.right) * 49) * breath * pose.squash;
    return math.Point(
      181 + x * math.cos(pose.lean) - y * math.sin(pose.lean) + 23,
      259 + pose.y + x * math.sin(pose.lean) + y * math.cos(pose.lean) - 3,
    );
  }

  const rest = math.Point(282.0, 239.0);
  if (t < .14) return rest;
  if (t < .25) {
    final u = (t - .14) / .11;
    final blend = u * u * (3 - 2 * u);
    final hand = atPaw(t);
    return rest + (hand - rest) * blend;
  }
  if (t <= .42) return atPaw(t);
  final release = atPaw(.42);
  if (t < .76) {
    final u = (t - .42) / .34;
    return math.Point(
      release.x + (316 - release.x) * u,
      release.y + (239 - release.y) * u - 4 * 35 * u * (1 - u),
    );
  }
  final bounce = ((t - .76) / .16).clamp(0.0, 1.0);
  return math.Point(316 + 6 * bounce, 239 - 4 * 10 * bounce * (1 - bounce));
}
