import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/album_page.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/ui.dart';

void main() {
  test(
    'Album uses saved events and never invents migrated or future facts',
    () {
      final state = GameState()..name = 'Листик';
      state.facts = [
        const DayFact(1, [15, 5, 20], [60, 20, 0], true, synthetic: true),
        const DayFact(2, [15, 5, 20], [60, 20, 0], false),
      ];
      state.completed.add('M01');
      state.owned.add('garden');
      final saved = jsonEncode(state.toJson());
      final entries = albumEntries(state);
      expect(
        entries.map((entry) => entry.id),
        containsAll(['friend', 'day:2', 'dream:garden', 'lessons']),
      );
      expect(
        entries.any(
          (entry) =>
              entry.id == 'day:1' ||
              entry.id == 'dream:house' ||
              entry.id == 'growth',
        ),
        isFalse,
      );
      expect(
        entries.firstWhere((entry) => entry.id == 'day:2').lines,
        contains('Подробные суммы этого дня не сохранились.'),
      );
      expect(
        entries.firstWhere((entry) => entry.id == 'lessons').lines,
        hasLength(1),
      );
      expect(jsonEncode(state.toJson()), saved);
    },
  );

  test('Album records durable choices, not consumed mandatory purchases', () {
    final state = GameState()..purchased.addAll({'food', 'shampoo'});
    expect(
      albumEntries(state).any((entry) => entry.id == 'purchases'),
      isFalse,
    );

    state.purchased.addAll({'ball', 'bow'});
    final purchases = albumEntries(
      state,
    ).singleWhere((entry) => entry.id == 'purchases');
    expect(purchases.lines, ['Разноцветный мяч', 'Праздничный бантик']);
    expect(purchases.lines, isNot(contains('Порция корма')));
    expect(purchases.lines, isNot(contains('Средства чистоты')));
  });

  testWidgets(
    'Album pages and owned stickers work at 320px with 200% text, without mutations',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = GameState()
        ..name = 'Листик'
        ..reducedMotion = true;
      state.purchased.add('stickers');
      state.completed.add('M01');
      final saved = jsonEncode(state.toJson());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AlbumPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Наш новый друг'), findsOneWidget);
      for (final title in ['Выбрали для дома', 'Уже умеем']) {
        await tester.tap(find.byTooltip('Следующая страница'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Следующая страница',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Предыдущая страница'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрали для дома'), findsOneWidget);
      expect(jsonEncode(state.toJson()), saved);
    },
  );
}
