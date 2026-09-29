import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/adoption_page.dart';
import 'package:kopilych/catalog_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/finance_intro.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('production adoption shows the financial purpose and choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pump();

    expect(find.byKey(const ValueKey('adopt-hint')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adopt-hint')));
    await tester.pumpAndSettle();
    expect(find.text(financeIntroPurpose), findsOneWidget);
    for (final decision in financeIntroDecisions) {
      expect(find.text(decision), findsOneWidget);
    }
    Navigator.of(tester.element(find.byType(FinanceIntroContent))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Котёнок'), findsOneWidget);
    expect(find.text('Щенок'), findsOneWidget);
    expect(find.text('Хомячок'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('adoption-room'))),
      const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home HUD names the selected goal at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GameState()
      ..name = 'Персик'
      ..goalId = 'garden';
    var openedStoryStep = 0;

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
          body: GameHome(
            state: state,
            scene: const ColoredBox(
              key: ValueKey('goal-room'),
              color: Colors.white,
            ),
            ready: true,
            busy: false,
            onRoom: (_) {},
            onCare: () {},
            onLamp: () {},
            onPlan: () {},
            onMission: () {},
            onDream: () {},
            onNextDay: () {},
            nextStepTitle: 'Сначала сравни цены',
            onNextStep: () => openedStoryStep++,
          ),
        ),
      ),
    );

    expect(find.textContaining('Маленький сад'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Сначала сравни цены'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('scene-status-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Сначала сравни цены'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('scene-show-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scene-show-next')));
    expect(openedStoryStep, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('goal-room'))),
      const Size(360, 800),
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(800, 360);
    await tester.pump();
    expect(find.textContaining('Маленький сад'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('goal-room'))),
      const Size(800, 360),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog explains purchases and offers honest next steps', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    addTearDown(() async => store?.close());
    final state = GameState()..wallet = [0, 70, 30];
    final controller = GameController(store!)..state = state;
    addTearDown(controller.dispose);
    var openedBudget = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: CatalogPage(
          controller: controller,
          onOpenBudget: () => openedBudget++,
          onAction: (label, action, {success, id}) async {
            fail('Insufficient purchase must not reach the transaction');
          },
        ),
      ),
    );

    expect(find.text('Обязательная забота · Цена: 10 монет'), findsOneWidget);
    expect(
      find.text('Результат: Повысит сытость на 25, до 100 максимум.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Разноцветный мяч'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Желание · Цена: 15 монет'), findsOneWidget);
    expect(
      find.textContaining('Результат: Повысит радость на 15'),
      findsOneWidget,
    );

    await tester.tap(find.text('Разноцветный мяч'));
    await tester.pumpAndSettle();
    expect(find.text('Пока не хватает монет'), findsOneWidget);
    expect(find.textContaining('Не хватает 15 монет'), findsOneWidget);
    expect(find.textContaining('В бюджете можно перевести'), findsOneWidget);
    expect(find.textContaining('оплачиваемое задание'), findsOneWidget);
    expect(find.text('Отложить покупку'), findsOneWidget);
    expect(find.text('Открыть бюджет'), findsOneWidget);
    await tester.tap(find.text('Открыть бюджет'));
    await tester.pumpAndSettle();
    expect(openedBudget, 1);
    expect(controller.state!.wallet, [0, 70, 30]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty wallets and exhausted income only offer real next steps', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    addTearDown(() async => store?.close());
    final state = GameState()
      ..wallet = [0, 0, 0]
      ..incomeClaimedDay = 1;
    final controller = GameController(store!)..state = state;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: CatalogPage(
          controller: controller,
          onOpenBudget: () => fail('There is nothing to transfer'),
          onAction: (label, action, {success, id}) async {
            fail('Insufficient purchase must not reach the transaction');
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Разноцветный мяч'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Разноцветный мяч'));
    await tester.pumpAndSettle();

    expect(find.text('Отложить покупку'), findsOneWidget);
    expect(find.text('Открыть бюджет'), findsNothing);
    expect(find.textContaining('перевести монеты'), findsNothing);
    expect(find.textContaining('оплачиваемое задание'), findsNothing);
    expect(
      find.textContaining('Доход этого периода уже получен'),
      findsOneWidget,
    );
    expect(
      find.textContaining('После итогов начни новый игровой период'),
      findsOneWidget,
    );
    expect(controller.state!.wallet, [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production preview repeats category price and result', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    addTearDown(() async => store?.close());
    final controller = GameController(store!)..state = GameState();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: CatalogPage(
          controller: controller,
          onAction: (label, action, {success, id}) async => true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Разноцветный мяч'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Разноцветный мяч'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Категория: желание.'), findsOneWidget);
    expect(
      find.textContaining('Результат: Повысит радость на 15'),
      findsOneWidget,
    );
    expect(
      find.text('Цена: 15 монет из «Сейчас» · останется 85'),
      findsOneWidget,
    );
    expect(controller.state!.wallet[0], 100);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mandatory catalog route returns care after it closes', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    addTearDown(() async => store?.close());
    final controller = GameController(store!)..state = GameState();
    addTearDown(controller.dispose);
    String? returnedAction;
    var prematureCallbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              returnedAction = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => CatalogPage(
                    controller: controller,
                    onSceneCare: (_) => prematureCallbacks++,
                    onAction: (label, action, {success, id}) async => true,
                  ),
                ),
              );
            },
            child: const Text('Открыть магазин'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть магазин'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Порция корма'));
    await tester.pumpAndSettle();

    expect(returnedAction, 'feed');
    expect(prematureCallbacks, 0);
    expect(find.text('Открыть магазин'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
