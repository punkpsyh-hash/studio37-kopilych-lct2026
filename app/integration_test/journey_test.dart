import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kopilych/main.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // GPU readback is optional; native adb capture is used for the delivery.
  const captureScreenshots = bool.fromEnvironment('CAPTURE_SCREENSHOTS');
  testWidgets(
    'Android: choose, learn, transfer, care, dream, reopen offline state',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      final path =
          '${await getDatabasesPath()}/journey-${DateTime.now().millisecondsSinceEpoch}.db';
      var store = await GameStore.open(path: path);
      await store.change(
        'settings',
        'Уменьшение движения',
        (s) => s.reducedMotion = true,
      );
      await tester.pumpWidget(KopilychApp(store: store));
      await tester.pumpAndSettle();
      Future<void> tapText(String text) async {
        final f = find.text(text).first;
        if (f.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            f,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        if (!captureScreenshots) return;
        final bytes = await binding.takeScreenshot(name);
        await File('${await getDatabasesPath()}/$name.png').writeAsBytes(bytes);
      }

      if (captureScreenshots) await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture('01-onboarding');
      await tapText('Хомячок');
      await tester.scrollUntilVisible(
        find.text('Это мой друг'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tapText('Шарфик');
      await tester.enterText(find.byType(TextField), 'Листик');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapText('Это мой друг');
      expect((await store.load()).name, 'Листик');
      expect((await store.load()).species, 2);
      await capture('02-home');
      await tapText('Задания');
      await tapText('Первые монеты');
      await tapText('30 монет');
      await tapText('Проверить решение');
      expect((await store.load()).total, 130);
      await capture('03-mission-result');
      await tapText('К своим планам');
      await tapText('Первые монеты');
      await tapText('30 монет');
      await tapText('Проверить решение');
      expect((await store.load()).total, 130);
      await tapText('К своим планам');
      await tapText('Бюджет');
      await capture('04-budget');
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '100');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapText('Перевести');
      expect((await store.load()).wallet, [30, 100, 0]);
      await tapText('Выбрать или исполнить мечту');
      await tapText(
        'Выбрать эту мечту',
      ); // First available alternative is the garden.
      await tapText('Исполнить мечту');
      expect((await store.load()).owned, contains('garden'));
      expect((await store.load()).wallet, [30, 0, 0]);
      await tapText('Дом');
      await tapText('Кормить');
      await tapText('Играть');
      await tapText('Купать');
      expect((await store.load()).wallet, [10, 0, 0]);
      expect((await store.load()).needs, [85, 85, 80]);
      await capture('05-care');
      await tapText('История');
      expect(find.text('Дом маленьких мечт'), findsOneWidget);
      expect(find.text('Глава 2 из 6'), findsOneWidget);
      await capture('06-story');
      final snapshot = (await store.load()).toJson();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      store = await GameStore.open(path: path);
      expect((await store.load()).toJson(), snapshot);
      await tester.pumpWidget(KopilychApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Листик · день 1'), findsOneWidget);
      await capture('06-restored');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    },
  );
}
