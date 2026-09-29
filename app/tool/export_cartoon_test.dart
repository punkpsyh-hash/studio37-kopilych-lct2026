import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/art.dart';
import 'package:kopilych/cartoon_props.dart';

// Authoring export: rasterizes the exact vector renderer used by the app.
// Run from app/: flutter test tool/export_cartoon_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Export original characters, props, sprite sheets and preview frames',
    () async {
      final font = FontLoader('Nunito')
        ..addFont(rootBundle.load('assets/fonts/Nunito-800.ttf'));
      await font.load();
      final out = Directory('../outputs/cartoon');
      await out.create(recursive: true);
      final frames = Directory('../work/cartoon-frames');
      await frames.create(recursive: true);
      const names = ['Персик', 'Бублик', 'Листик'];
      const ids = ['cat', 'puppy', 'forest'];
      const colors = [0, 4, 2];
      void label(
        Canvas c,
        String text,
        double x,
        double y, {
        double size = 22,
        Color color = const Color(0xFF354A50),
      }) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: size,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 1050);
        painter.paint(c, Offset(x, y));
      }

      void pet(
        Canvas c,
        int species,
        Rect r,
        PetAction action,
        double t, {
        bool room = false,
        bool transparent = true,
      }) {
        c.save();
        c.translate(r.left, r.top);
        PetPainter(
          species: species,
          color: petColors[colors[species]],
          accessory: species == 1 ? 2 : 1,
          room: room,
          owned: const {'house', 'garden', 'stars'},
          phase: t,
          action: action,
          actionProgress: t,
          stage: 1,
          transparent: transparent,
        ).paint(c, r.size);
        c.restore();
      }

      Future<void> render(
        String path,
        int width,
        int height,
        void Function(Canvas) draw,
      ) async {
        final recorder = ui.PictureRecorder();
        final c = Canvas(recorder);
        draw(c);
        final pic = recorder.endRecording();
        final image = await pic.toImage(width, height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        pic.dispose();
      }

      await render('${out.path}/character-sheet.png', 1080, 830, (c) {
        c.drawColor(const Color(0xFFFFFAF2), BlendMode.src);
        label(c, 'Копилыч · маленькие друзья', 36, 28, size: 34);
        label(c, 'Три характера. Одна большая дружба.', 36, 79, size: 19);
        for (var i = 0; i < 3; i++) {
          pet(c, i, Rect.fromLTWH(i * 360, 120, 360, 310), PetAction.idle, .2);
          label(c, names[i], i * 360 + 115, 437, size: 25);
          pet(
            c,
            i,
            Rect.fromLTWH(i * 360, 471, 360, 310),
            PetAction.values[i + 1],
            .42,
          );
          label(c, actionLabels[i + 1], i * 360 + 75, 780, size: 20);
        }
      });
      await render('${out.path}/prop-sheet.png', 960, 300, (c) {
        c.drawColor(const Color(0xFFFFFAF2), BlendMode.src);
        label(c, 'Маленькие вещи для большого счастья', 30, 20, size: 27);
        const propNames = [
          'Корм',
          'Мяч',
          'Мыло',
          'Любовь',
          'Домик',
          'Сад',
          'Свет',
          'Монетка',
        ];
        for (var i = 0; i < CartoonProp.values.length; i++) {
          drawProp(
            c,
            CartoonProp.values[i],
            Rect.fromLTWH(i * 120 + 12, 95, 96, 96),
          );
          label(c, propNames[i], i * 120 + 22, 215, size: 17);
        }
      });
      for (var species = 0; species < 3; species++) {
        await render(
          '${out.path}/${ids[species]}.png',
          720,
          620,
          (c) => pet(
            c,
            species,
            const Rect.fromLTWH(0, 0, 720, 620),
            PetAction.idle,
            .2,
          ),
        );
        for (final action in PetAction.values) {
          await render(
            '${out.path}/${ids[species]}-${action.name}-strip.png',
            2160,
            620,
            (c) {
              for (var frame = 0; frame < 12; frame++) {
                pet(
                  c,
                  species,
                  Rect.fromLTWH(
                    (frame % 6) * 360,
                    (frame ~/ 6) * 310,
                    360,
                    310,
                  ),
                  action,
                  frame / 12,
                );
              }
            },
          );
        }
      }
      for (var i = 0; i < CartoonProp.values.length; i++) {
        await render(
          '${out.path}/prop-${CartoonProp.values[i].name}.png',
          256,
          256,
          (c) => drawProp(
            c,
            CartoonProp.values[i],
            const Rect.fromLTWH(0, 0, 256, 256),
          ),
        );
      }
      // 12 seconds, 10 fps: three action scenes followed by a shared affection clip.
      for (var frame = 0; frame < 120; frame++) {
        final segment = frame ~/ 30, t = (frame % 30) / 30;
        await render(
          '${frames.path}/${frame.toString().padLeft(4, '0')}.png',
          1080,
          570,
          (c) {
            c.drawColor(const Color(0xFFFFFAF2), BlendMode.src);
            label(c, 'Копилыч · живая мультяшная графика', 28, 18, size: 29);
            for (var i = 0; i < 3; i++) {
              final action = segment == 3
                  ? PetAction.love
                  : PetAction.values[1 + (i + segment) % 3];
              pet(
                c,
                i,
                Rect.fromLTWH(i * 360 + 8, 80, 344, 310),
                action,
                t,
                room: true,
              );
              label(
                c,
                '${names[i]} · ${actionLabels[action.index]}',
                i * 360 + 20,
                415,
                size: 19,
              );
            }
            for (var i = 0; i < 8; i++) {
              drawProp(
                c,
                CartoonProp.values[i],
                Rect.fromLTWH(155 + i * 96, 474, 62, 62),
              );
            }
          },
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
