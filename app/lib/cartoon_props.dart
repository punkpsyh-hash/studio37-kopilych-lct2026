import 'package:flutter/material.dart';

enum CartoonProp {
  bowl,
  ball,
  soap,
  heart,
  house,
  garden,
  lamp,
  coin,
  sofa,
  bath,
  clipboard,
  menu,
  plus,
  water,
}

class PropArt extends StatelessWidget {
  const PropArt(this.prop, {super.key, this.size = 48});
  final CartoonProp prop;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      'assets/art/ui-cozy/${switch (prop) {
        CartoonProp.bowl => 'food',
        CartoonProp.ball => 'play-ball',
        CartoonProp.soap => 'soap',
        CartoonProp.heart => 'heart',
        CartoonProp.house => 'home',
        CartoonProp.garden => 'garden',
        CartoonProp.lamp => 'lamp',
        CartoonProp.coin => 'coin',
        CartoonProp.sofa => 'living-room',
        CartoonProp.bath => 'bathroom',
        CartoonProp.clipboard => 'job-checklist',
        CartoonProp.menu => 'menu',
        CartoonProp.plus => 'plus',
        CartoonProp.water => 'water',
      }}.webp',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
        64,
        256,
      ),
      excludeFromSemantics: true,
    ),
  );
}

/// All props share a 64 × 64 canvas, soft contours and an original palette.
void drawProp(
  Canvas canvas,
  CartoonProp prop,
  Rect bounds, {
  double rotation = 0,
}) {
  final c = canvas;
  final p = Paint()..isAntiAlias = true;
  const outline = Color(0xFF675948);
  void path(Path shape, Color fill, {bool stroke = true}) {
    final bounds = shape.getBounds();
    c.drawPath(
      shape,
      p
        ..color = fill
        ..shader = fill.a == 1 && !bounds.isEmpty
            ? RadialGradient(
                center: const Alignment(-.45, -.65),
                radius: 1.25,
                colors: [
                  Color.lerp(fill, Colors.white, .28)!,
                  fill,
                  Color.lerp(fill, outline, .25)!,
                ],
                stops: const [0, .55, 1],
              ).createShader(shape.getBounds())
            : null
        ..style = PaintingStyle.fill,
    );
    if (stroke) {
      c.drawPath(
        shape,
        p
          ..shader = null
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeJoin = StrokeJoin.round,
      );
    }
    p
      ..style = PaintingStyle.fill
      ..shader = null;
  }

  void oval(Rect r, Color fill, {bool stroke = true}) =>
      path(Path()..addOval(r), fill, stroke: stroke);
  void box(Rect r, double radius, Color fill) => path(
    Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius))),
    fill,
  );
  c.save();
  c.translate(bounds.left, bounds.top);
  c.scale(bounds.width / 64, bounds.height / 64);
  c.translate(32, 32);
  c.rotate(rotation);
  c.translate(-32, -32);
  switch (prop) {
    case CartoonProp.bowl:
      oval(
        const Rect.fromLTWH(7, 48, 50, 9),
        const Color(0x20594932),
        stroke: false,
      );
      path(
        Path()
          ..moveTo(9, 31)
          ..lineTo(55, 31)
          ..lineTo(50, 52)
          ..quadraticBezierTo(32, 59, 14, 52)
          ..close(),
        const Color(0xFF8A9E59),
      );
      oval(const Rect.fromLTWH(8, 23, 48, 18), const Color(0xFFDCE9E0));
      oval(const Rect.fromLTWH(13, 27, 38, 9), const Color(0xFF735B42));
      for (var i = 0; i < 7; i++) {
        oval(
          Rect.fromLTWH(16 + (i % 4) * 8, 25 + (i ~/ 4) * 5, 7, 6),
          const Color(0xFFBD895B),
          stroke: false,
        );
      }
      oval(
        const Rect.fromLTWH(28, 44, 8, 6),
        const Color(0xFFFFFAEB),
        stroke: false,
      );
      for (var i = 0; i < 3; i++) {
        oval(
          Rect.fromLTWH(26 + i * 4, 40, 3, 4),
          const Color(0xFFFFFAEB),
          stroke: false,
        );
      }
    case CartoonProp.ball:
      oval(const Rect.fromLTWH(8, 8, 48, 48), const Color(0xFFF0BF64));
      c.save();
      c.clipPath(Path()..addOval(const Rect.fromLTWH(8, 8, 48, 48)));
      path(
        Path()
          ..moveTo(33, 5)
          ..quadraticBezierTo(16, 30, 48, 59)
          ..lineTo(66, 42)
          ..quadraticBezierTo(36, 36, 49, 3)
          ..close(),
        const Color(0xFF4B9D99),
      );
      path(
        Path()
          ..moveTo(3, 42)
          ..quadraticBezierTo(18, 25, 26, 7)
          ..lineTo(6, 3)
          ..close(),
        const Color(0xFF4B9D99),
      );
      c.restore();
      oval(
        const Rect.fromLTWH(16, 14, 10, 6),
        const Color(0xAAFFFFFF),
        stroke: false,
      );
    case CartoonProp.soap:
      box(const Rect.fromLTWH(10, 24, 44, 28), 10, const Color(0xFF8FC5D9));
      box(const Rect.fromLTWH(15, 28, 34, 15), 7, const Color(0xFFC6E7ED));
      for (final pos in [
        const Offset(18, 17),
        const Offset(36, 12),
        const Offset(48, 19),
      ]) {
        oval(Rect.fromCircle(center: pos, radius: 7), const Color(0xFFDDEFF0));
        oval(
          Rect.fromCircle(center: pos - const Offset(2, 2), radius: 2),
          Colors.white,
          stroke: false,
        );
      }
    case CartoonProp.heart:
      path(
        Path()
          ..moveTo(32, 55)
          ..cubicTo(7, 38, 1, 25, 12, 15)
          ..cubicTo(20, 8, 29, 13, 32, 20)
          ..cubicTo(38, 7, 52, 10, 57, 21)
          ..cubicTo(63, 34, 46, 46, 32, 55)
          ..close(),
        const Color(0xFFEB8074),
      );
      oval(
        const Rect.fromLTWH(16, 18, 8, 5),
        const Color(0x88FFFFFF),
        stroke: false,
      );
    case CartoonProp.house:
      box(const Rect.fromLTWH(11, 25, 42, 31), 4, const Color(0xFFEAC595));
      path(
        Path()
          ..moveTo(5, 29)
          ..lineTo(32, 7)
          ..lineTo(59, 29)
          ..lineTo(54, 35)
          ..lineTo(32, 17)
          ..lineTo(10, 35)
          ..close(),
        const Color(0xFFC87641),
      );
      box(const Rect.fromLTWH(23, 34, 18, 23), 9, const Color(0xFF846B51));
      oval(
        const Rect.fromLTWH(26, 43, 12, 8),
        const Color(0xFFBCCCAC),
        stroke: false,
      );
    case CartoonProp.garden:
      box(const Rect.fromLTWH(5, 40, 54, 18), 5, const Color(0xFFD6A078));
      for (var i = 0; i < 3; i++) {
        final x = 16 + i * 16.0;
        path(
          Path()
            ..moveTo(x, 42)
            ..lineTo(x, 20),
          const Color(0xFF799E7D),
        );
        oval(Rect.fromLTWH(x - 10, 24, 12, 7), const Color(0xFF9EB98B));
        oval(Rect.fromLTWH(x, 29, 12, 7), const Color(0xFF88A582));
        oval(
          Rect.fromCircle(center: Offset(x, 17 + (i % 2) * 5), radius: 7),
          i == 1 ? const Color(0xFFF0C16F) : const Color(0xFFE7ADAD),
        );
        oval(
          Rect.fromCircle(center: Offset(x, 17 + (i % 2) * 5), radius: 2),
          const Color(0xFFFFF5DC),
          stroke: false,
        );
      }
    case CartoonProp.lamp:
      path(
        Path()
          ..moveTo(32, 28)
          ..lineTo(32, 54),
        outline,
      );
      oval(const Rect.fromLTWH(18, 50, 28, 8), const Color(0xFFB5C4D6));
      path(
        Path()
          ..moveTo(32, 5)
          ..lineTo(39, 20)
          ..lineTo(56, 22)
          ..lineTo(44, 34)
          ..lineTo(47, 51)
          ..lineTo(32, 42)
          ..lineTo(17, 51)
          ..lineTo(20, 34)
          ..lineTo(8, 22)
          ..lineTo(25, 20)
          ..close(),
        const Color(0xFFF3CF7E),
      );
      oval(const Rect.fromLTWH(25, 25, 3, 5), outline, stroke: false);
      oval(const Rect.fromLTWH(37, 25, 3, 5), outline, stroke: false);
    case CartoonProp.coin:
      oval(const Rect.fromLTWH(9, 6, 46, 52), const Color(0xFFE4B454));
      oval(const Rect.fromLTWH(14, 11, 36, 42), const Color(0xFFF9D980));
      oval(
        const Rect.fromLTWH(23, 32, 19, 15),
        const Color(0xFFC18A29),
        stroke: false,
      );
      for (final toe in [
        const Rect.fromLTWH(19, 25, 7, 9),
        const Rect.fromLTWH(27, 20, 7, 9),
        const Rect.fromLTWH(36, 22, 7, 9),
        const Rect.fromLTWH(43, 28, 6, 8),
      ]) {
        oval(toe, const Color(0xFFC18A29), stroke: false);
      }
    case CartoonProp.sofa:
      box(const Rect.fromLTWH(11, 49, 7, 10), 2, const Color(0xFF986A41));
      box(const Rect.fromLTWH(46, 49, 7, 10), 2, const Color(0xFF986A41));
      box(const Rect.fromLTWH(10, 11, 44, 32), 12, const Color(0xFF718B48));
      box(const Rect.fromLTWH(16, 16, 15, 23), 7, const Color(0xFF9CB375));
      box(const Rect.fromLTWH(33, 16, 15, 23), 7, const Color(0xFF91A967));
      box(const Rect.fromLTWH(10, 35, 44, 18), 7, const Color(0xFF829B57));
      box(const Rect.fromLTWH(5, 29, 12, 24), 6, const Color(0xFF728B48));
      box(const Rect.fromLTWH(47, 29, 12, 24), 6, const Color(0xFF728B48));
      box(const Rect.fromLTWH(19, 35, 26, 9), 5, const Color(0xFFA6B982));
    case CartoonProp.bath:
      box(const Rect.fromLTWH(15, 48, 6, 11), 2, const Color(0xFF947954));
      box(const Rect.fromLTWH(43, 48, 6, 11), 2, const Color(0xFF947954));
      path(
        Path()
          ..moveTo(7, 30)
          ..lineTo(57, 30)
          ..lineTo(51, 46)
          ..quadraticBezierTo(32, 58, 13, 46)
          ..close(),
        const Color(0xFF91BED2),
      );
      box(const Rect.fromLTWH(4, 26, 56, 9), 4, const Color(0xFFFFFBED));
      for (final bubble in [
        const Rect.fromLTWH(13, 18, 12, 12),
        const Rect.fromLTWH(29, 13, 18, 17),
        const Rect.fromLTWH(42, 7, 9, 9),
      ]) {
        oval(bubble, const Color(0xFFC8E8EB));
        oval(
          Rect.fromCircle(
            center: bubble.center - const Offset(2, 2),
            radius: 2,
          ),
          Colors.white,
          stroke: false,
        );
      }
    case CartoonProp.clipboard:
      c.rotate(.05);
      box(const Rect.fromLTWH(12, 9, 42, 50), 6, const Color(0xFFB58652));
      box(const Rect.fromLTWH(16, 14, 33, 40), 3, const Color(0xFFFFF3D0));
      box(const Rect.fromLTWH(23, 5, 20, 10), 4, const Color(0xFFD2AE71));
      for (var row = 0; row < 3; row++) {
        final y = 24.0 + row * 10;
        path(
          Path()
            ..moveTo(21, y)
            ..lineTo(24, y + 3)
            ..lineTo(29, y - 3),
          const Color(0xFF6F854B),
        );
        box(
          Rect.fromLTWH(33, y - 1, row == 1 ? 9 : 12, 2.5),
          1,
          const Color(0xFF8D7958),
        );
      }
    case CartoonProp.menu:
      oval(const Rect.fromLTWH(4, 5, 56, 55), const Color(0xFFB78956));
      oval(const Rect.fromLTWH(7, 6, 50, 48), const Color(0xFFCBA16D));
      for (var row = 0; row < 3; row++) {
        box(
          Rect.fromLTWH(16, 17 + row * 12.0, 32, 6),
          3,
          const Color(0xFFFFF3D3),
        );
      }
    case CartoonProp.plus:
      oval(const Rect.fromLTWH(5, 5, 54, 54), const Color(0xFF7E9F4F));
      box(const Rect.fromLTWH(16, 28, 32, 8), 3, const Color(0xFFFFF9DE));
      box(const Rect.fromLTWH(28, 16, 8, 32), 3, const Color(0xFFFFF9DE));
    case CartoonProp.water:
      path(
        Path()
          ..moveTo(8, 33)
          ..lineTo(56, 33)
          ..lineTo(51, 51)
          ..quadraticBezierTo(32, 59, 13, 51)
          ..close(),
        const Color(0xFF8BA675),
      );
      oval(const Rect.fromLTWH(7, 26, 50, 17), const Color(0xFFFFF4D9));
      oval(const Rect.fromLTWH(12, 29, 40, 10), const Color(0xFF8FC4D8));
      path(
        Path()
          ..moveTo(34, 3)
          ..cubicTo(28, 13, 22, 17, 25, 23)
          ..cubicTo(31, 33, 46, 26, 39, 16)
          ..close(),
        const Color(0xFF8FCBDD),
      );
      oval(const Rect.fromLTWH(28, 18, 4, 6), Colors.white, stroke: false);
  }
  c.restore();
}
