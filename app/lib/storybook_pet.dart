import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pet_motion.dart';

/// Transparent articulated object, reconstructed from storybook-v2 references.
/// Hierarchy: floor → body → shoulders, neck → face/ears; tail has its own pivot.
class StorybookPet {
  StorybookPet(this.c, this.fur, this.species);
  final Canvas c;
  final Color fur;
  final int species;
  static const outline = Color(0xFF705039);
  static const milk = Color(0xFFFFEBD0);
  Color get shadow => Color.lerp(fur, const Color(0xFF795133), .32)!;
  Color get light => Color.lerp(fur, const Color(0xFFFFE9B6), .42)!;

  void shape(Path path, Color color, {bool volume = true, double edge = 1.15}) {
    final r = path.getBounds();
    final paint = Paint()..isAntiAlias = true;
    if (volume && color.a == 1) {
      paint.shader = RadialGradient(
        center: const Alignment(-.45, -.55),
        radius: 1.2,
        colors: [
          Color.lerp(color, Colors.white, .18)!,
          color,
          Color.lerp(color, outline, .22)!,
        ],
        stops: const [0, .6, 1],
      ).createShader(r);
    } else {
      paint.color = color;
    }
    c.drawPath(path, paint);
    if (edge > 0) {
      c.drawPath(
        path,
        Paint()
          ..color = Color.lerp(color, outline, .58)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = edge
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void oval(
    double x,
    double y,
    double w,
    double h,
    Color color, {
    double edge = 0,
  }) => shape(Path()..addOval(Rect.fromLTWH(x, y, w, h)), color, edge: edge);
  void stroke(Path path, Color color, double width) => c.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  void draw(
    PetPose pose,
    double phase,
    PetAction action,
    double progress,
    int accessory, {
    double speechMouth = 0,
  }) {
    final cycle = phase * math.pi * 2;
    final presence = action == PetAction.idle ? 0.0 : motionPresence(progress);
    // Contact shadow stays on the floor and gets smaller during flight.
    final shadowSize = 1 + pose.y / 100;
    c.save();
    c.translate(181, 260);
    c.scale(shadowSize, shadowSize);
    oval(-60, -4, 120, 15, const Color(0x279A7350));
    c.restore();
    c.save();
    c.translate(181, 259 + pose.y);
    c.rotate(pose.lean);
    c.scale(1 / math.sqrt(pose.squash), pose.squash);
    c.translate(-181, -259);
    // The tail follows the body with a slower overlapping action.
    c.save();
    c.translate(220, 229);
    c.rotate(
      math.sin(cycle - .7) * .07 +
          math.sin(progress * math.pi * 4 - .6) * .15 * presence,
    );
    shape(
      Path()
        ..moveTo(-3, 2)
        ..cubicTo(32, 20, 61, -3, 54, -27)
        ..cubicTo(49, -46, 28, -34, 35, -23)
        ..cubicTo(40, -12, 33, -1, 16, -7)
        ..quadraticBezierTo(5, -12, -3, 2)
        ..close(),
      shadow,
    );
    shape(
      Path()
        ..moveTo(38, -33)
        ..cubicTo(50, -39, 59, -22, 51, -13)
        ..quadraticBezierTo(41, -17, 35, -23)
        ..quadraticBezierTo(32, -29, 38, -33)
        ..close(),
      milk,
      edge: .5,
    );
    c.restore();
    final breath = math.sin(cycle) * .009;
    c.save();
    c.translate(181, 259);
    c.scale(1 + breath, 1 + breath);
    c.translate(-181, -259);
    shape(
      Path()
        ..moveTo(155, 178)
        ..cubicTo(139, 187, 132, 213, 135, 240)
        ..cubicTo(135, 264, 226, 266, 227, 240)
        ..cubicTo(230, 212, 218, 184, 206, 178)
        ..quadraticBezierTo(181, 166, 155, 178)
        ..close(),
      fur,
    );
    shape(
      Path()
        ..moveTo(177, 184)
        ..cubicTo(153, 200, 152, 239, 167, 252)
        ..quadraticBezierTo(182, 261, 198, 251)
        ..cubicTo(211, 235, 205, 201, 185, 184)
        ..lineTo(181, 189)
        ..close(),
      milk,
      edge: .4,
    );
    oval(128, 239, 41, 23, light, edge: 1);
    oval(194, 239, 41, 23, light, edge: 1);
    for (final x in [140.0, 151.0, 207.0, 218.0]) {
      stroke(
        Path()
          ..moveTo(x, 253)
          ..quadraticBezierTo(x - 1, 256, x, 258),
        shadow,
        .85,
      );
    }
    for (final side in [-1, 1]) {
      c.save();
      c.translate(181 + side * 32, 197);
      c.rotate(side < 0 ? pose.left : pose.right);
      shape(
        Path()
          ..moveTo(-10, -5)
          ..cubicTo(-18, 9, -16, 36, -10, 49)
          ..cubicTo(-6, 58, 13, 57, 14, 46)
          ..cubicTo(12, 24, 10, 6, 7, -3)
          ..quadraticBezierTo(0, -10, -10, -5)
          ..close(),
        fur,
      );
      oval(-12, 40, 25, 17, milk, edge: .65);
      for (final x in [-4.0, 4.0]) {
        stroke(
          Path()
            ..moveTo(x, 51)
            ..lineTo(x, 55),
          shadow,
          .65,
        );
      }
      c.restore();
    }
    c.restore();
    c.save();
    c.translate(181, 177 + pose.nod + math.sin(cycle - .3) * .65);
    final chew = action == PetAction.feed && progress > .3 && progress < .67
        ? math.sin(progress * math.pi * 30) * .017
        : 0.0;
    c.rotate(pose.head + math.sin(cycle - .8) * .012 + chew);
    c.translate(0, -30);
    for (final side in [-1, 1]) {
      c.save();
      c.translate(side * 48, -39);
      c.rotate(
        side *
            (math.sin(cycle - .8) * .014 +
                presence * math.sin(progress * 14 - 1) * .04),
      );
      c.scale(side.toDouble(), 1);
      if (species == 0) {
        shape(
          Path()
            ..moveTo(-14, 7)
            ..cubicTo(-19, -15, -13, -46, 6, -64)
            ..cubicTo(22, -58, 36, -16, 21, 13)
            ..close(),
          fur,
        );
        shape(
          Path()
            ..moveTo(-7, -4)
            ..quadraticBezierTo(-8, -36, 7, -50)
            ..quadraticBezierTo(24, -22, 17, 3)
            ..close(),
          const Color(0xFFEAB09A),
          edge: .6,
        );
        stroke(
          Path()
            ..moveTo(-4, -16)
            ..quadraticBezierTo(1, -33, 6, -35),
          milk,
          4,
        );
      } else if (species == 1) {
        shape(
          Path()
            ..moveTo(-9, -22)
            ..cubicTo(26, -32, 39, 5, 39, 37)
            ..cubicTo(37, 67, 4, 72, -3, 43)
            ..cubicTo(-11, 22, -11, 1, -9, -22)
            ..close(),
          shadow,
        );
        stroke(
          Path()
            ..moveTo(21, -1)
            ..cubicTo(33, 18, 29, 39, 21, 46),
          light,
          2,
        );
      } else {
        shape(
          Path()
            ..moveTo(-9, 9)
            ..cubicTo(-33, -11, -33, -43, -37, -60)
            ..cubicTo(0, -65, 37, -37, 17, 1)
            ..quadraticBezierTo(3, 11, -9, 9)
            ..close(),
          fur,
        );
        stroke(
          Path()
            ..moveTo(3, 3)
            ..quadraticBezierTo(-5, -29, -29, -49),
          shadow,
          1.6,
        );
        for (var i = 0; i < 3; i++) {
          stroke(
            Path()
              ..moveTo(-4 - i * 7, -10 - i * 12)
              ..lineTo(9 - i * 6, -26 - i * 8),
            shadow,
            .8,
          );
        }
      }
      c.restore();
    }
    shape(
      Path()
        ..moveTo(-65, -20)
        ..cubicTo(-68, -51, -36, -68, -11, -62)
        ..quadraticBezierTo(-6, -71, -2, -78)
        ..quadraticBezierTo(6, -68, 5, -62)
        ..quadraticBezierTo(17, -68, 18, -76)
        ..quadraticBezierTo(28, -65, 20, -58)
        ..cubicTo(46, -61, 65, -43, 65, -18)
        ..quadraticBezierTo(65, -7, 72, -3)
        ..lineTo(67, 1)
        ..lineTo(76, 6)
        ..quadraticBezierTo(70, 16, 61, 20)
        ..lineTo(65, 23)
        ..cubicTo(47, 48, -47, 48, -65, 23)
        ..lineTo(-61, 20)
        ..quadraticBezierTo(-71, 15, -76, 6)
        ..lineTo(-67, 1)
        ..lineTo(-72, -3)
        ..quadraticBezierTo(-65, -7, -65, -20)
        ..close(),
      fur,
      edge: 1.25,
    );
    shape(
      Path()
        ..moveTo(-59, 16)
        ..cubicTo(-48, 4, -32, 13, -17, 17)
        ..quadraticBezierTo(0, 10, 17, 17)
        ..cubicTo(32, 13, 48, 4, 59, 16)
        ..cubicTo(52, 50, -52, 50, -59, 16)
        ..close(),
      milk,
      edge: 0,
    );
    if (species == 0) {
      for (final x in [-17.0, 0.0, 17.0]) {
        shape(
          Path()
            ..moveTo(x - 5, -57)
            ..quadraticBezierTo(x, -26, x + 3, -41)
            ..lineTo(x + 4, -59)
            ..close(),
          shadow,
          edge: 0,
        );
      }
    } else if (species == 1) {
      shape(
        Path()
          ..moveTo(-4, -60)
          ..cubicTo(-21, -42, -15, -5, -4, 9)
          ..quadraticBezierTo(4, 14, 8, 5)
          ..cubicTo(20, -20, 14, -47, 7, -60)
          ..close(),
        milk,
        edge: 0,
      );
    } else {
      c.save();
      c.translate(2, -60);
      c.rotate(math.sin(cycle - 1) * .06);
      stroke(
        Path()
          ..moveTo(0, 4)
          ..quadraticBezierTo(2, -14, -1, -22),
        shadow,
        2,
      );
      shape(
        Path()
          ..moveTo(0, -15)
          ..quadraticBezierTo(-26, -34, -22, -37)
          ..quadraticBezierTo(2, -37, 0, -15)
          ..close(),
        light,
        edge: .8,
      );
      shape(
        Path()
          ..moveTo(1, -9)
          ..quadraticBezierTo(8, -35, 25, -30)
          ..quadraticBezierTo(22, -11, 1, -9)
          ..close(),
        fur,
        edge: .8,
      );
      c.restore();
    }
    final blink = phase > .92 && phase < .98
        ? math.sin((phase - .92) / .06 * math.pi)
        : 0.0;
    final closed = math.max(blink, pose.eyes);
    for (final side in [-1, 1]) {
      c.save();
      c.translate(side * 29, -6);
      if (closed > .84) {
        stroke(
          Path()
            ..moveTo(-12, 2)
            ..quadraticBezierTo(0, -10, 12, 2),
          outline,
          2.5,
        );
      } else {
        c.scale(1, 1 - closed * .8);
        oval(-17, -21, 34, 43, const Color(0xFFFFF9EC), edge: 1);
        oval(
          -12,
          -16,
          25,
          34,
          species == 1 ? const Color(0xFF99612F) : const Color(0xFF6D8B48),
          edge: .9,
        );
        oval(-8, -12, 17, 27, const Color(0xFF26321E));
        oval(-6, -12, 8, 10, Colors.white);
        oval(5, 6, 3, 3, const Color(0xFFFDF6DB));
        stroke(
          Path()
            ..moveTo(-15, -10)
            ..quadraticBezierTo(-6, -28, 12, -17),
          outline,
          2,
        );
      }
      stroke(
        Path()
          ..moveTo(-11, -31)
          ..quadraticBezierTo(0, -38, 9, -31),
        shadow,
        2.3,
      );
      c.restore();
    }
    oval(-52, 14, 20, 7, const Color(0x35D78C7B));
    oval(32, 14, 20, 7, const Color(0x35D78C7B));
    shape(
      Path()
        ..moveTo(-7, 15)
        ..quadraticBezierTo(0, 11, 7, 15)
        ..quadraticBezierTo(7, 20, 0, 23)
        ..quadraticBezierTo(-7, 20, -7, 15)
        ..close(),
      species == 0 ? const Color(0xFFB96D46) : outline,
      edge: .7,
    );
    oval(-4, 14, 5, 2, const Color(0xFFFFD3A7));
    stroke(
      Path()
        ..moveTo(0, 23)
        ..lineTo(0, 26)
        ..quadraticBezierTo(-5, 34, -11, 27),
      outline,
      1.55,
    );
    stroke(
      Path()
        ..moveTo(0, 26)
        ..quadraticBezierTo(5, 34, 11, 27),
      outline,
      1.55,
    );
    if (action == PetAction.feed && progress > .3 && progress < .68) {
      oval(-4, 28, 8, 3 + chew.abs() * 180, const Color(0xFFAD6254));
    }
    if (speechMouth > .04) {
      final opening = speechMouth.clamp(0.0, 1.0);
      oval(
        -5 - opening * 2,
        27,
        10 + opening * 4,
        3 + opening * 10,
        const Color(0xFF804A43),
      );
      oval(-3, 29 + opening * 6, 6, 2 + opening * 2, const Color(0xFFE7A29A));
    }
    // Short fur accents follow the silhouette, not random noise.
    for (final side in [-1, 1]) {
      for (var i = 0; i < 3; i++) {
        stroke(
          Path()
            ..moveTo(side * (49 + i * 2), 19 + i * 4)
            ..lineTo(side * (57 + i * 2), 17 + i * 4),
          light,
          .8,
        );
      }
      if (species == 0) {
        for (var i = 0; i < 2; i++) {
          stroke(
            Path()
              ..moveTo(side * 46, 23 + i * 5)
              ..lineTo(side * 73, 19 + i * 10),
            shadow,
            .75,
          );
        }
      }
    }
    if (accessory == 3) {
      // The shop cap follows the animated head in the 2D fallback.
      shape(
        Path()
          ..moveTo(-59, -54)
          ..quadraticBezierTo(-51, -101, 0, -102)
          ..quadraticBezierTo(51, -101, 59, -54)
          ..close(),
        const Color(0xFFD96C5F),
        edge: 1,
      );
      oval(-62, -62, 124, 17, const Color(0xFFB84F44), edge: 1);
      oval(-9, -109, 18, 16, const Color(0xFFF3D9A4));
    }
    c.restore();
    if (accessory == 1 || accessory == 2 || accessory == 4) {
      c.save();
      c.translate(181, 198 + pose.nod * .12);
      if (accessory == 1) {
        shape(
          Path()
            ..moveTo(-30, -1)
            ..quadraticBezierTo(0, 12, 30, -1)
            ..lineTo(24, 8)
            ..quadraticBezierTo(0, 18, -29, 8)
            ..close(),
          const Color(0xFFC97456),
        );
        shape(
          Path()
            ..moveTo(-4, 9)
            ..lineTo(21, 11)
            ..lineTo(5, 34)
            ..quadraticBezierTo(-5, 20, -4, 9)
            ..close(),
          const Color(0xFFE28D69),
        );
        stroke(
          Path()
            ..moveTo(7, 13)
            ..lineTo(6, 26),
          const Color(0xFFAE5B45),
          1,
        );
      } else {
        for (final side in [-1, 1]) {
          shape(
            Path()
              ..moveTo(0, 5)
              ..lineTo(side * 22, -5)
              ..quadraticBezierTo(side * 27, 6, side * 22, 17)
              ..close(),
            const Color(0xFFBD7569),
          );
        }
        oval(-5, 1, 10, 11, const Color(0xFFD99B7D), edge: 1);
      }
      c.restore();
    }
    c.restore();
  }
}
