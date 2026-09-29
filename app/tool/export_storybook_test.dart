import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/art.dart';
import 'package:kopilych/cartoon_props.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = '../outputs/storybook';
  const frames = '../work/storybook-frames';
  void pet(
    Canvas c,
    int species,
    Rect r,
    PetAction action,
    double t, {
    bool room = false,
    bool transparent = true,
    double? phase,
  }) {
    c.save();
    c.translate(r.left, r.top);
    PetPainter(
      species: species,
      color: petColors[[0, 5, 2][species]],
      accessory: 1,
      room: room,
      owned: const {'house', 'garden', 'stars'},
      phase: phase ?? t,
      action: action,
      actionProgress: t,
      stage: 1,
      transparent: transparent,
    ).paint(c, r.size);
    c.restore();
  }

  Future<void> render(
    String path,
    int w,
    int h,
    void Function(Canvas) draw,
  ) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    draw(c);
    final pic = recorder.endRecording();
    final im = await pic.toImage(w, h);
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    im.dispose();
    pic.dispose();
  }

  void label(Canvas c, String text, double x, double y, {double size = 24}) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Nunito',
          color: const Color(0xFF594631),
          fontSize: size,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1080);
    p.paint(c, Offset(x, y));
  }

  setUpAll(() async {
    await Directory(out).create(recursive: true);
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito-800.ttf'))).load();
  });
  test('key poses and transparent objects', () async {
    await render('$out/characters.png', 1080, 430, (c) {
      c.drawColor(const Color(0xFFFFF7E9), BlendMode.src);
      label(c, 'Дом маленьких мечт · герои', 28, 22, size: 31);
      for (var i = 0; i < 3; i++) {
        pet(c, i, Rect.fromLTWH(i * 360, 66, 360, 310), PetAction.idle, .25);
        label(c, ['Персик', 'Бублик', 'Листик'][i], i * 360 + 130, 385);
      }
    });
    for (var i = 0; i < 3; i++) {
      await render(
        '$out/${['cat', 'puppy', 'forest'][i]}.png',
        720,
        620,
        (c) =>
            pet(c, i, const Rect.fromLTWH(0, 0, 720, 620), PetAction.idle, 0),
      );
      for (final action in PetAction.values) {
        await render(
          '$out/${['cat', 'puppy', 'forest'][i]}-${action.name}-strip.png',
          2160,
          620,
          (c) {
            for (var f = 0; f < 12; f++) {
              pet(
                c,
                i,
                Rect.fromLTWH((f % 6) * 360, (f ~/ 6) * 310, 360, 310),
                action,
                f / 12,
              );
            }
          },
        );
      }
    }
    await render('$out/motion-poses.png', 1440, 420, (c) {
      c.drawColor(const Color(0xFFFFF7E9), BlendMode.src);
      for (var i = 0; i < 4; i++) {
        pet(
          c,
          0,
          Rect.fromLTWH(i * 360, 25, 360, 310),
          PetAction.play,
          [.14, .23, .42, .66][i],
        );
        label(
          c,
          ['Подготовка', 'Толчок', 'Полёт', 'Приземление'][i],
          i * 360 + 70,
          353,
        );
      }
    });
    await render('$out/props.png', 960, 180, (c) {
      c.drawColor(const Color(0xFFFFF7E9), BlendMode.src);
      for (var i = 0; i < 8; i++) {
        drawProp(
          c,
          CartoonProp.values[i],
          Rect.fromLTWH(i * 120 + 10, 20, 100, 100),
        );
      }
    });
  });
  test('30 fps motion preview', () async {
    await Directory(frames).create(recursive: true);
    for (var frame = 0; frame < 432; frame++) {
      final action = PetAction.values[frame ~/ 72];
      final t = (frame % 72) / 72;
      await render(
        '$frames/${frame.toString().padLeft(4, '0')}.png',
        1080,
        500,
        (c) {
          c.drawColor(const Color(0xFFFFF7E9), BlendMode.src);
          label(c, 'Дом маленьких мечт', 32, 22, size: 31);
          label(
            c,
            [
              'Знакомство',
              'Кормление',
              'Игра',
              'Купание',
              'Объятия',
              'Праздник',
            ][action.index],
            32,
            66,
            size: 21,
          );
          for (var i = 0; i < 3; i++) {
            pet(
              c,
              i,
              Rect.fromLTWH(i * 360, 125, 360, 310),
              action,
              t,
              phase: (frame / 30 / 3.2) % 1,
            );
          }
          label(
            c,
            'Ключевые позы, дуги движения и мягкое завершение',
            32,
            457,
            size: 19,
          );
        },
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
