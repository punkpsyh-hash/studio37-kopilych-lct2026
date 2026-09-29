import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/art.dart';

void main() {
  testWidgets(
    'Export the Flutter pet with the actual generated speech envelope',
    (tester) async {
      await tester.runAsync(() async {
        final audio = await File(
          '../outputs/voice/pet-voice-preview.wav',
        ).readAsBytes();
        final data = audio.buffer.asByteData();
        expect(data.getUint16(34, Endian.little), 16);
        final sampleRate = data.getUint32(24, Endian.little);
        final count = (audio.length - 44) ~/ 2;
        final duration = count / sampleRate;
        final directory = Directory('../work/voice-frames');
        await directory.create(recursive: true);
        for (var frame = 0; frame < (duration * 24).ceil(); frame++) {
          final start = (frame / 24 * sampleRate).floor();
          final end = math.min(start + sampleRate ~/ 24, count);
          var energy = 0.0;
          for (var i = start; i < end; i++) {
            final v = data.getInt16(44 + i * 2, Endian.little) / 32768;
            energy += v * v;
          }
          final mouth = (math.sqrt(energy / math.max(1, end - start)) * 8)
              .clamp(0.0, 1.0);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          PetPainter(
            species: 0,
            color: petColors[0],
            accessory: 1,
            room: true,
            owned: const {'house'},
            phase: (frame / 24 / 3.2) % 1,
            stage: 2,
            speechMouth: mouth,
          ).paint(canvas, const Size(720, 620));
          final picture = recorder.endRecording();
          final image = await picture.toImage(720, 620);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/frame-${frame.toString().padLeft(4, '0')}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
      });
    },
  );
}
