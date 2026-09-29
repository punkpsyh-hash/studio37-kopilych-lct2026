import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/story_page.dart';
import 'package:kopilych/ui.dart';

void main() {
  testWidgets(
    'Story at 200% text stays scrollable and routes to the actual next task',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? target;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: StoryPage(
              state: GameState()..name = 'Персик',
              onGo: (value) => target = value,
              onCelebrate: () {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Сравнить три мечты и выбрать свою'),
        220,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Сравнить три мечты и выбрать свою'),
      );
      expect(target, 'S01');
      expect(find.text('Собрать учебную корзину необходимого'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
