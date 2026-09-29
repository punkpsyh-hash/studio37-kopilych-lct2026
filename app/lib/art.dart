import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cartoon_props.dart';
import 'pet_motion.dart';
import 'storybook_pet.dart';
export 'pet_motion.dart' show PetAction;

const petColors = [
  Color(0xFFE9AA70),
  Color(0xFFB9B5DD),
  Color(0xFFACC7B1),
  Color(0xFFE5B7B8),
  Color(0xFF9EBCD6),
  Color(0xFFD1BE9F),
];

const actionLabels = [
  'Привет!',
  'Вкусно!',
  'Давай играть!',
  'Чисто и пушисто!',
  'Обнимашки!',
  'У нас получилось!',
];

/// Original vector artwork. Coordinates use a 360 × 310 design canvas.
class PetScene extends StatefulWidget {
  const PetScene({
    super.key,
    required this.species,
    required this.color,
    this.accessory = 0,
    this.room = true,
    this.transparent = false,
    this.showDecor = false,
    this.effectsOnly = false,
    this.reducedMotion = false,
    this.owned = const {},
    this.purchased = const {},
    this.reaction = 0,
    this.action = PetAction.love,
    this.stage = 1,
    this.speechMouth = 0,
    this.listening = false,
  });
  final int species, color, accessory, reaction, stage;
  final PetAction action;
  final bool room, transparent, showDecor, effectsOnly, reducedMotion;
  final Set<String> owned;

  /// Предметы из магазина, показанные в комнате (мяч, наклейки, шапочка, ночник).
  final Set<String> purchased;
  final double speechMouth;
  final bool listening;
  @override
  State<PetScene> createState() => _PetSceneState();
}

class _PetSceneState extends State<PetScene>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final AnimationController _effect = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
    value: 1,
  );
  Timer? _staticTimer;
  bool _staticReaction = false;
  PetPose? _transitionFrom;
  double _smoothMouth = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get still =>
      widget.reducedMotion || MediaQuery.of(context).disableAnimations;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PetScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (widget.reaction != oldWidget.reaction && widget.reaction > 0) {
      _transitionFrom = _effect.value < 1
          ? samplePetMotion(oldWidget.action, _effect.value)
          : null;
      _staticTimer?.cancel();
      _staticReaction = false;
      if (still) {
        _staticReaction = true;
        _staticTimer = Timer(const Duration(milliseconds: 2400), () {
          if (mounted) setState(() => _staticReaction = false);
        });
      } else {
        _effect.forward(from: 0);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
    } else {
      _animation.stop();
      _effect.value = 1;
    }
  }

  void _sync() {
    if (still) {
      _animation.stop();
      _effect.value = 1;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _staticTimer?.cancel();
    _effect.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: Listenable.merge([_animation, _effect]),
      builder: (context, child) => CustomPaint(
        painter: PetPainter(
          species: widget.species,
          color: petColors[widget.color],
          accessory: widget.accessory,
          room: widget.room,
          transparent: widget.transparent,
          showDecor: widget.showDecor,
          effectsOnly: widget.effectsOnly,
          owned: widget.owned,
          purchased: widget.purchased,
          phase: still ? 0 : _animation.value,
          action: _staticReaction || _effect.value < 1
              ? widget.action
              : PetAction.idle,
          actionProgress: _staticReaction ? .42 : _effect.value,
          stage: widget.stage,
          transitionFrom: _transitionFrom,
          speechMouth: _smoothMouth = still
              ? 0
              : _smoothMouth + (widget.speechMouth - _smoothMouth) * .3,
          listening: widget.listening,
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class PetPainter extends CustomPainter {
  PetPainter({
    required this.species,
    required this.color,
    required this.accessory,
    required this.room,
    required this.owned,
    this.purchased = const {},
    required this.phase,
    this.action = PetAction.idle,
    this.actionProgress = 0,
    this.transparent = false,
    this.showDecor = false,
    this.effectsOnly = false,
    this.transitionFrom,
    required this.stage,
    this.speechMouth = 0,
    this.listening = false,
  });
  final int species, accessory, stage;
  final Color color;
  final bool room, transparent, showDecor, effectsOnly;
  final PetAction action;
  final double actionProgress;
  final PetPose? transitionFrom;
  final double speechMouth;
  final bool listening;
  bool get happy => action != PetAction.idle;
  double get energy => math.sin(actionProgress.clamp(0, 1) * math.pi);
  final Set<String> owned;
  final Set<String> purchased;
  final double phase;
  static const ink = Color(0xFF493E39);
  final p = Paint()..isAntiAlias = true;
  void oval(Canvas c, double x, double y, double w, double h, Color color) {
    c.drawOval(
      Rect.fromLTWH(x, y, w, h),
      p
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void box(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    double r,
    Color color,
  ) {
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
      p
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void line(Canvas c, List<Offset> points, Color color, double width) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    c.drawPath(
      path,
      p
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    p.style = PaintingStyle.fill;
  }

  void shape(Canvas c, Path path, Color color) {
    c.drawPath(
      path,
      p
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void star(Canvas c, double x, double y, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * .46;
      final xx = x + math.cos(a) * rr, yy = y + math.sin(a) * rr;
      if (i == 0) {
        path.moveTo(xx, yy);
      } else {
        path.lineTo(xx, yy);
      }
    }
    shape(c, path..close(), color);
  }

  void plant(Canvas c, double x, double y) {
    line(c, [Offset(x, y + 22), Offset(x, y - 23)], const Color(0xFF6B947F), 4);
    oval(c, x - 22, y - 28, 23, 13, const Color(0xFF84AC8A));
    oval(c, x, y - 17, 24, 14, const Color(0xFF9ABC95));
    oval(c, x - 17, y - 3, 19, 12, const Color(0xFF729C81));
    shape(
      c,
      Path()
        ..moveTo(x - 16, y + 13)
        ..lineTo(x + 16, y + 13)
        ..lineTo(x + 11, y + 40)
        ..lineTo(x - 11, y + 40)
        ..close(),
      const Color(0xFFCD8F70),
    );
    box(c, x - 18, y + 11, 36, 7, 3, const Color(0xFFE0A080));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = canvas;
    c.save();
    c.scale(size.width / 360, size.height / 310);
    if (room) {
      box(c, 0, 0, 360, 310, 28, const Color(0xFFF4EBDD));
      box(c, 0, 220, 360, 90, 0, const Color(0xFFE7D7BF));
      box(c, 0, 218, 360, 7, 0, const Color(0xFFDCCAB0));
      for (var i = 0; i < 6; i++) {
        line(
          c,
          [Offset(i * 80 - 60, 310), Offset(i * 65, 225)],
          const Color(0xFFDBC8AE),
          1,
        );
      }
      // Arched morning window.
      box(c, 25, 24, 105, 150, 50, const Color(0xFFDCC9AF));
      box(c, 32, 31, 91, 134, 44, const Color(0xFFD8EAF0));
      oval(c, 77, 48, 26, 26, const Color(0xFFFFD38E));
      oval(c, 40, 83, 38, 15, const Color(0xFFF8FCF8));
      oval(c, 51, 74, 20, 21, const Color(0xFFF8FCF8));
      box(c, 32, 132, 91, 33, 0, const Color(0xFFBBD0B7));
      oval(c, 57, 119, 86, 35, const Color(0xFFA5C6AD));
      box(c, 75, 33, 5, 134, 0, const Color(0xFFF4EBDD));
      box(c, 31, 103, 94, 5, 0, const Color(0xFFF4EBDD));
      box(c, 23, 165, 110, 8, 4, const Color(0xFFBE9D7B));
      // Wall art and a shelf with tiny books.
      box(c, 249, 36, 57, 66, 7, const Color(0xFFD4B28C));
      box(c, 255, 42, 45, 54, 3, const Color(0xFFFFF9EC));
      star(c, 277, 67, 16, const Color(0xFFDFAC60));
      box(c, 233, 150, 104, 8, 3, const Color(0xFFBC9471));
      box(c, 242, 121, 13, 29, 2, const Color(0xFFB4C9B7));
      box(c, 257, 116, 11, 34, 2, const Color(0xFFDCA995));
      box(c, 270, 126, 15, 24, 2, const Color(0xFFE7C77D));
      plant(c, 313, 111);
      oval(c, 64, 238, 234, 53, const Color(0xFFC1C8AA));
      oval(c, 76, 242, 210, 40, const Color(0xFFDCE0C8));
      if (owned.contains('house')) {
        shape(
          c,
          Path()
            ..moveTo(10, 239)
            ..lineTo(10, 203)
            ..lineTo(44, 175)
            ..lineTo(78, 203)
            ..lineTo(78, 239)
            ..close(),
          const Color(0xFFC49770),
        );
        box(c, 28, 209, 29, 30, 14, const Color(0xFF7A6651));
        line(
          c,
          [const Offset(6, 204), const Offset(44, 171), const Offset(82, 204)],
          const Color(0xFF987657),
          7,
        );
      } else {
        plant(c, 35, 201);
      }
      if (owned.contains('garden')) {
        plant(c, 321, 218);
        plant(c, 289, 228);
      }
      if (owned.contains('stars')) {
        line(
          c,
          [const Offset(211, 0), const Offset(211, 48)],
          const Color(0xFFBE9D7B),
          2,
        );
        star(c, 211, 61, 18, const Color(0xFFEFBF62));
      }
      // Предметы из магазина.
      if (purchased.contains('ball')) {
        oval(c, 118, 252, 26, 26, const Color(0xFFD96C5F));
        oval(c, 124, 257, 14, 9, const Color(0xFFF3D9A4));
      }
      if (purchased.contains('stickers')) {
        star(c, 268, 52, 7, const Color(0xFF8CA994));
        star(c, 286, 70, 5, const Color(0xFFD96C5F));
        star(c, 262, 84, 4, const Color(0xFF7CA3BF));
      }
      if (purchased.contains('nightlight')) {
        box(c, 40, 130, 16, 20, 4, const Color(0xFF7CA3BF));
        star(c, 48, 138, 6, const Color(0xFFF3D98B));
      }
    } else if (!transparent) {
      oval(c, 33, 42, 294, 251, const Color(0xFFF3E8D8));
      star(c, 62, 96, 9, const Color(0xFFDBB66B));
      star(c, 304, 176, 6, const Color(0xFF8CA994));
      oval(c, 271, 64, 12, 12, const Color(0xFFE5CDB2));
    }
    if (transparent && showDecor) {
      // Keep earned and purchased decorations visible on the new living-room plate.
      if (owned.contains('house')) {
        shape(
          c,
          Path()
            ..moveTo(10, 239)
            ..lineTo(10, 203)
            ..lineTo(44, 175)
            ..lineTo(78, 203)
            ..lineTo(78, 239)
            ..close(),
          const Color(0xFFC49770),
        );
        box(c, 28, 209, 29, 30, 14, const Color(0xFF7A6651));
      }
      if (owned.contains('garden')) {
        plant(c, 321, 218);
        plant(c, 289, 228);
      }
      if (owned.contains('stars')) {
        line(
          c,
          [const Offset(211, 0), const Offset(211, 48)],
          const Color(0xFFBE9D7B),
          2,
        );
        star(c, 211, 61, 18, const Color(0xFFEFBF62));
      }
      if (purchased.contains('ball')) {
        oval(c, 118, 252, 26, 26, const Color(0xFFD96C5F));
        oval(c, 124, 257, 14, 9, const Color(0xFFF3D9A4));
      }
      if (purchased.contains('stickers')) {
        star(c, 268, 52, 7, const Color(0xFF8CA994));
        star(c, 286, 70, 5, const Color(0xFFD96C5F));
        star(c, 262, 84, 4, const Color(0xFF7CA3BF));
      }
      if (purchased.contains('nightlight')) {
        box(c, 40, 130, 16, 20, 4, const Color(0xFF7CA3BF));
        star(c, 48, 138, 6, const Color(0xFFF3D98B));
      }
    }
    final target = listening && action == PetAction.idle
        ? const PetPose(head: -.12, nod: -3, left: -.10, right: .10)
        : samplePetMotion(action, actionProgress);
    final blend = (actionProgress / .12).clamp(0.0, 1.0);
    final pose = transitionFrom == null || action == PetAction.idle
        ? target
        : PetPose.mix(transitionFrom!, target, blend * blend * (3 - 2 * blend));
    if (!effectsOnly) {
      StorybookPet(c, color, species).draw(
        pose,
        phase,
        action,
        actionProgress,
        accessory,
        speechMouth: speechMouth,
      );
    }
    if (!effectsOnly && stage > 1) {
      star(c, 181, 231 + pose.y, 6, const Color(0xFFE5B65E));
    }
    if (!effectsOnly && stage == 3) {
      for (var i = 0; i < 3; i++) {
        star(
          c,
          158 + i * 23,
          28 + (i == 1 ? -7 : 0),
          5,
          const Color(0xFFE5B65E),
        );
      }
    }
    _effects(c);
    c.restore();
  }

  void _effects(Canvas c) {
    if (!happy) return;
    final t = actionProgress;
    final opacity = motionPresence(t);
    c.saveLayer(
      const Rect.fromLTWH(0, 0, 360, 310),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    // Props have their own timeline; financial state is never touched here.
    if (action == PetAction.feed) {
      drawProp(c, CartoonProp.bowl, const Rect.fromLTWH(139, 195, 86, 68));
      for (var i = 0; i < 4; i++) {
        final rise = (t * 2 + i * .23) % 1;
        oval(c, 170 + i * 8, 225 - rise * 42, 4, 4, const Color(0xFFB88350));
      }
    } else if (action == PetAction.play) {
      // The lift is attached to the paw; release and floor bounce are separate.
      final toss = ((t - .16) / .55).clamp(0.0, 1.0);
      final ball = playBallPosition(t, phase);
      drawProp(
        c,
        CartoonProp.ball,
        Rect.fromCenter(center: Offset(ball.x, ball.y), width: 40, height: 40),
        rotation: toss * math.pi * 2,
      );
      star(c, 99, 183, 7 + energy * 3, const Color(0xFFE7B758));
    } else if (action == PetAction.bath) {
      drawProp(c, CartoonProp.soap, const Rect.fromLTWH(253, 219, 57, 47));
      for (var i = 0; i < 9; i++) {
        final rise = (t * .8 + i * .137) % 1;
        final x = 112 + (i % 4) * 44.0 + math.sin(t * math.pi * 3 + i) * 6;
        final y = 258 - rise * 116;
        final r = 5.0 + (i % 3) * 3;
        oval(c, x, y, r * 2, r * 2, const Color(0xAADCEDF2));
        c.drawCircle(
          Offset(x + r, y + r),
          r,
          p
            ..color = const Color(0xFF96C4D7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        p.style = PaintingStyle.fill;
        oval(c, x + r * .5, y + r * .35, r * .6, r * .6, Colors.white);
      }
      for (var i = 0; i < 6; i++) {
        oval(
          c,
          137 + i * 14,
          250 - (i % 2) * 5,
          25,
          18,
          const Color(0xFFF7FFFF),
        );
      }
    } else if (action == PetAction.celebrate) {
      for (var i = 0; i < 14; i++) {
        final u = ((t - .2) / .8).clamp(0.0, 1.0);
        final x = 181 + math.sin(i * 2.4) * u * 150;
        final y = 105 - math.sin(u * math.pi) * 65 + u * u * 155;
        star(
          c,
          x,
          y + i % 3 * 9,
          2.5 + i % 3,
          [
            const Color(0xFFEAB865),
            const Color(0xFF72AA9C),
            const Color(0xFFD48B78),
          ][i % 3],
        );
      }
    } else {
      for (var i = 0; i < 4; i++) {
        final rise = (t + i * .21) % 1;
        drawProp(
          c,
          CartoonProp.heart,
          Rect.fromLTWH(
            i.isEven ? 84.0 : 251.0,
            200 - rise * 103,
            22 + energy * 8,
            22 + energy * 8,
          ),
        );
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant PetPainter oldDelegate) => true;
}
