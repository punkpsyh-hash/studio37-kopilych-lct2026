import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/adoption_page.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/ui.dart';

void main() {
  testWidgets('hamster opens a separate preview and coat updates the scene', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AdoptionPage(
          busy: false,
          onStart: (species, color, accessory, name) async => true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('adopt-choose-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('adopt-start')), findsNothing);
    expect(find.textContaining('Заботься о питомце'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('adopt-species-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('adopt-personalize-stage')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('adopt-start')), findsOneWidget);
    var room = tester.widget<SharedRoom>(find.byType(SharedRoom));
    expect(room.sceneState['species'], 'hamster');
    expect(room.sceneState['adoptionOpen'], isTrue);
    await tester.tap(find.byKey(const ValueKey('adopt-coat-1')));
    await tester.pumpAndSettle();
    room = tester.widget<SharedRoom>(find.byType(SharedRoom));
    expect(room.sceneState['color'], 'fur_02');

    await tester.tap(find.byKey(const ValueKey('adopt-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adopt-choose-stage')), findsOneWidget);
    room = tester.widget<SharedRoom>(find.byType(SharedRoom));
    expect(room.sceneState['adoptionOpen'], isFalse);
  });

  testWidgets('full coat names remain readable at 360px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-400.ttf'));
    await tester.runAsync(font.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdoptionPage(
          busy: false,
          onStart: (species, color, accessory, name) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Котёнок'));
    await tester.pumpAndSettle();
    final label = find.text('Серебристый полосатый');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    expect(label, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    expect(tester.getRect(label).right, lessThanOrEqualTo(360));
    expect(find.text('Рыжий'), findsOneWidget);
    expect(find.text('Кремовый'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
