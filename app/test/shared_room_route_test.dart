import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/scene_bridge.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/canon_lesson.dart';
import 'package:kopilych/canon_lesson_page.dart';
import 'package:kopilych/finance_intro.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Platform extends WebViewPlatform {
  late _Controller controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _Widget(params);
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  PageEventCallback? finished;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  JavaScriptChannelParams? channel;
  _Navigation? navigation;
  final scripts = <String>[];
  bool sent = false;
  String? visualIdentity;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> enableZoom(bool enabled) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigation = handler as _Navigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    navigation?.finished?.call(params.uri.toString());
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    const marker = 'window.KopilychScene?.setState(';
    if (script.startsWith(marker)) {
      final state =
          jsonDecode(script.substring(marker.length, script.length - 2))
              as Map<String, dynamic>;
      final identity = jsonEncode([
        state['mode'],
        state['species'],
        state['color'],
        state['adoptionOpen'],
      ]);
      if (!sent || identity != visualIdentity) {
        sent = true;
        visualIdentity = identity;
        // Platform-channel replies arrive after the synchronous widget update.
        await Future<void>.value();
        send({...state, 'mode': state['mode'] ?? 'home', 'type': 'ready'});
      }
    }
  }

  void send(Map<String, dynamic> value) =>
      channel?.onMessageReceived(JavaScriptMessage(message: jsonEncode(value)));
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.green);
}

void main() {
  for (final care in [
    (
      action: 'feed',
      species: 0,
      room: 'kitchen',
      index: 0,
      price: 10,
      title: 'Покормить Пушок?',
      effect: 'Сытость станет 85 из 100.',
      purchase: 'food_refill',
    ),
    (
      action: 'clean',
      species: 2,
      room: 'bathroom',
      index: 2,
      price: 5,
      title: 'Почистить шёрстку в песочной ванночке?',
      effect: 'Чистота станет 80 из 100.',
      purchase: 'clean_care',
    ),
  ]) {
    testWidgets(
      'AC05 scene-channel ${care.action} previews, cancels, persists once and replays free',
      (tester) async {
        final previous = WebViewPlatform.instance;
        final platform = _Platform();
        WebViewPlatform.instance = platform;
        addTearDown(() {
          if (previous != null) WebViewPlatform.instance = previous;
        });
        tester.view.physicalSize = const Size(432, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        sqfliteFfiInit();
        final store = (await tester.runAsync(
          () => GameStore.open(
            path: inMemoryDatabasePath,
            factory: databaseFactoryFfi,
          ),
        ))!;
        addTearDown(() => tester.runAsync(store.close));
        await tester.runAsync(
          () => store.change('care-fixture', 'Готовый первый план', (state) {
            state.name = 'Пушок';
            state.species = care.species;
            state.soundEnabled = false;
            state.setCurrentRoom(care.room);
            state.confirmPlan([15, 35, 50]);
          }),
        );
        final controller = GameController(store);
        addTearDown(controller.dispose);
        await tester.runAsync(controller.load);

        Future<void> waitFor(bool Function() done) async {
          for (var attempt = 0; attempt < 60; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pumpAndSettle();
            if (done()) return;
          }
          fail('Scene-channel reply and SQLite should settle');
        }

        Future<void> openShell() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              home: GameShell(controller: controller),
            ),
          );
          await waitFor(() {
            final room =
                find.byType(SharedRoom).evaluate().single as StatefulElement;
            return !controller.busy &&
                room.state is SharedRoomState &&
                (room.state as SharedRoomState).ready;
          });
          expect(platform.controller.channel, isNotNull);
          expect(controller.state!.currentRoom, care.room);
        }

        List<Map<String, dynamic>> replies(String id) {
          const prefix = 'window.KopilychScene?.resolveAction(';
          return platform.controller.scripts
              .where((script) => script.startsWith(prefix))
              .map(
                (script) =>
                    jsonDecode(
                          script.substring(prefix.length, script.length - 2),
                        )
                        as Map<String, dynamic>,
              )
              .where((reply) => reply['id'] == id)
              .toList();
        }

        void send(String id) => platform.controller.send({
          'type': 'action',
          'id': id,
          'action': care.action,
          'room': care.room,
        });

        Future<({String state, String history, String events})>
        snapshot() async {
          return (await tester.runAsync(() async {
            return (
              state: jsonEncode((await store.load()).toJson()),
              history: jsonEncode(await store.history()),
              events: jsonEncode(await store.financialHistory()),
            );
          }))!;
        }

        void expectPreview({required bool free}) {
          final dialog = find.byType(AlertDialog);
          expect(dialog, findsOneWidget);
          expect(
            find.descendant(of: dialog, matching: find.text(care.title)),
            findsOneWidget,
          );
          final text = tester
              .widgetList<Text>(
                find.descendant(of: dialog, matching: find.byType(Text)),
              )
              .map((widget) => widget.data ?? '')
              .join('\n');
          expect(text, contains('Обязательная забота.'));
          if (free) {
            expect(
              text,
              contains(
                'Показатель уже обновлён после сегодняшней заботы; повторим только действие.',
              ),
            );
            expect(
              text,
              contains(
                'За эту заботу сегодня уже заплачено. Повтор бесплатный.',
              ),
            );
            expect(find.text('Да · бесплатно'), findsOneWidget);
          } else {
            expect(text, contains(care.effect));
            expect(
              text,
              contains(
                'Потратим ${care.price} монет. В конверте «Сейчас» останется ${100 - care.price}.',
              ),
            );
            expect(find.text('Да · ${care.price} монет'), findsOneWidget);
          }
          if (care.species == 2) {
            expect(text, contains('песочной ванночке'));
            expect(
              text.toLowerCase(),
              isNot(matches(RegExp('вод|мыть|купать'))),
            );
          }
        }

        await openShell();
        final before = await snapshot();
        final beforeController = jsonEncode(controller.state!.toJson());
        final cancelId = 'ac05:${care.action}:cancel';
        send(cancelId);
        await tester.pumpAndSettle();
        expectPreview(free: false);
        expect(await snapshot(), before);
        expect(jsonEncode(controller.state!.toJson()), beforeController);
        expect(replies(cancelId), isEmpty);
        await tester.tap(find.text('Позже'));
        await waitFor(() => replies(cancelId).isNotEmpty);
        expect(replies(cancelId).single['accepted'], false);
        expect(find.byType(AlertDialog), findsNothing);
        expect(await snapshot(), before);
        expect(jsonEncode(controller.state!.toJson()), beforeController);

        final paidId = 'ac05:${care.action}:paid';
        send(paidId);
        await tester.pumpAndSettle();
        // A duplicate while the confirmation is open must not create another dialog.
        send(paidId);
        await tester.pumpAndSettle();
        expectPreview(free: false);
        expect(await snapshot(), before);
        expect(replies(paidId), isEmpty);
        await tester.tap(find.text('Да · ${care.price} монет'));
        await waitFor(() => !controller.busy && replies(paidId).isNotEmpty);
        expect(replies(paidId).single['accepted'], true);
        final saved = (await tester.runAsync(store.load))!;
        expect(saved.wallet, [100 - care.price, 0, 0]);
        expect(saved.needs, care.index == 0 ? [85, 65, 55] : [60, 65, 80]);
        expect(saved.cared, {care.index});
        expect(saved.purchased, {care.purchase});
        expect(saved.completed, isEmpty);
        expect(saved.periodActivity.mandatorySpent, care.price);
        expect(controller.state!.toJson(), saved.toJson());
        final history = (await tester.runAsync(store.history))!;
        expect(history, hasLength(3));
        expect(history.first['id'], 'scene:$paidId');
        expect(history.first['delta'], -care.price);
        expect(history[1]['id'], startsWith('resume:'));
        final events = (await tester.runAsync(store.financialHistory))!;
        expect(
          events.where((event) => event['operation_id'] == 'scene:$paidId'),
          hasLength(1),
        );
        final expense = events.where((event) => event['kind'] == 'care').single;
        expect(expense['operation_id'], 'scene:$paidId');
        expect(expense['category'], 'mandatory');
        expect(expense['amount'], care.price);
        expect(expense['from_wallet'], 0);
        expect(expense['period'], saved.day);

        final paid = await snapshot();
        send(paidId);
        await waitFor(() => replies(paidId).length == 2);
        expect(replies(paidId).last['accepted'], true);
        expect(find.byType(AlertDialog), findsNothing);
        expect(await snapshot(), paid);

        // Recreate the scene to clear its in-memory ID cache, then read SQLite again.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.load);
        await openShell();
        send(paidId);
        await tester.pumpAndSettle();
        expectPreview(free: true);
        expect(await snapshot(), paid);
        await tester.tap(find.text('Да · бесплатно'));
        await waitFor(() => !controller.busy && replies(paidId).isNotEmpty);
        expect(replies(paidId).single['accepted'], true);
        expect(await snapshot(), paid);

        final repeatId = 'ac05:${care.action}:repeat';
        send(repeatId);
        await tester.pumpAndSettle();
        expectPreview(free: true);
        expect(await snapshot(), paid);
        await tester.tap(find.text('Да · бесплатно'));
        await waitFor(() => !controller.busy && replies(repeatId).isNotEmpty);
        expect(replies(repeatId).single['accepted'], true);
        expect((await snapshot()).state, paid.state);
        expect(controller.state!.toJson(), saved.toJson());
        final repeatedHistory = (await tester.runAsync(store.history))!;
        expect(repeatedHistory, hasLength(4));
        expect(repeatedHistory.first['id'], 'scene:$repeatId');
        expect(repeatedHistory.first['delta'], 0);
        final repeatedEvents = (await tester.runAsync(store.financialHistory))!;
        expect(
          repeatedEvents.where((event) => event['kind'] == 'care').toList(),
          [expense],
        );
        final repeatEvent = repeatedEvents
            .where((event) => event['operation_id'] == 'scene:$repeatId')
            .single;
        expect(repeatEvent['kind'], 'state');
        expect(repeatEvent['amount'], 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('production shell routes home menu and persists S01 B02 P01', (
    tester,
  ) async {
    final previous = WebViewPlatform.instance;
    WebViewPlatform.instance = _Platform();
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    tester.view.physicalSize = const Size(432, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final store = (await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = GameController(store);
    await tester.runAsync(controller.load);

    Future<void> settleIo() async {
      for (var attempt = 0; attempt < 60; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        final rooms = find.byType(SharedRoom).evaluate();
        if (!controller.busy &&
            rooms.isNotEmpty &&
            rooms.every((element) {
              if (element is! StatefulElement) return false;
              final roomState = element.state;
              return roomState is SharedRoomState && roomState.ready;
            })) {
          return;
        }
      }
      fail('Controlled WebView readiness and SQLite should settle');
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller),
      ),
    );
    await settleIo();
    expect(controller.state!.name, isNull);
    await tester.tap(find.byKey(const ValueKey('adopt-hint')));
    await tester.pumpAndSettle();
    expect(find.text(financeIntroPurpose), findsOneWidget);
    Navigator.of(tester.element(find.byType(FinanceIntroContent))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хомячок'));
    await settleIo();
    final adopt = find.byKey(const ValueKey('adopt-start'));
    await tester.ensureVisible(adopt);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(adopt).onPressed, isNotNull);
    await tester.tap(adopt);
    await settleIo();
    expect(controller.state!.species, 2);
    expect(controller.state!.name, isNotNull);
    expect(find.byType(GameHome), findsOneWidget);
    expect(
      tester.widget<SharedRoom>(find.byType(SharedRoom)).sceneState['species'],
      'hamster',
    );
    expect(controller.state!.wallet, [100, 0, 0]);
    expect(find.text('О, мячик! Поиграем в гостиной.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scene-show-next-collapsed')),
      findsOneWidget,
    );

    // Open the visible 3D home menu: help remains available after adoption.
    await tester.tap(find.byKey(const ValueKey('scene-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Как играть'));
    await tester.pumpAndSettle();
    expect(find.text(financeIntroPurpose), findsOneWidget);
    Navigator.of(tester.element(find.byType(FinanceIntroContent))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scene-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Словарик'));
    await tester.pumpAndSettle();
    expect(find.text('Обязательные расходы'), findsOneWidget);
    expect(find.text('Накопления'), findsOneWidget);
    Navigator.of(tester.element(find.byType(FinanceGlossaryContent))).pop();
    await tester.pumpAndSettle();

    // Exercise the production 3D home's menu routes with real taps.
    for (final destination in ['Бюджет', 'Задания', 'История']) {
      await tester.tap(find.byKey(const ValueKey('scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      expect(find.text(destination), findsWidgets);
      expect(find.byKey(const ValueKey('back-to-home')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('back-to-home')));
      await settleIo();
      expect(find.byType(GameHome), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('scene-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Громкость звуков: 100%'), findsOneWidget);
    Navigator.of(tester.element(find.text('Громкость звуков: 100%'))).pop();
    await settleIo();
    await tester.tap(find.byKey(const ValueKey('scene-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Итоги дня'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Сначала составь план этого дня'),
      findsOneWidget,
    );
    expect(controller.state!.day, 1);
    // The floating notice sits over the HUD's next-step row until it hides.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // The room dock can move directly between every pair of rooms.
    for (final room in ['kitchen', 'bathroom', 'living']) {
      await tester.tap(find.byKey(ValueKey('scene-room-$room')));
      await settleIo();
      expect(controller.state!.currentRoom, room);
    }

    // This part checks the existing canonical lesson route for older saves.
    await tester.runAsync(
      () => controller.change(
        'Legacy route',
        (state) => state.completed.remove('intro-started'),
      ),
    );
    await settleIo();

    for (final id in ['S01', 'B02', 'P01']) {
      if (id == 'S01') {
        await tester.tap(find.byKey(const ValueKey('scene-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('История').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(
            FilledButton,
            'Сравнить три мечты и выбрать свою',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            'Сравнить три мечты и выбрать свою',
          ),
        );
      } else {
        await tester.tap(find.byKey(const ValueKey('scene-show-next')));
      }
      await tester.pumpAndSettle();
      final page = tester.widget<CanonLessonPage>(find.byType(CanonLessonPage));
      expect(page.lessonId, id);
      final command = CanonLessonSubmission.capture(
        controller.state!,
        lessonId: id,
        practice: false,
        goalId: id == 'S01' ? 'garden' : null,
        split: id == 'B02' ? [15, 15, 30] : null,
        basketIds: id == 'P01' ? ['food_refill', 'clean_care'] : [],
        rationale: id == 'P01' ? 'Корм и чистота нужны питомцу сегодня' : null,
      );
      final receipt = await tester.runAsync(() => page.onSubmit(command));
      final reward = receipt!.reward;
      expect(reward, id == 'P01' ? 30 : 0);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(CanonLessonPage))).pop();
      if (id == 'S01') {
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('back-to-home')));
        await settleIo();
      } else {
        await settleIo();
      }
      expect(controller.state!.completed, contains('canon:$id:1'));
    }
    expect(controller.state!.wallet, [130, 0, 0]);
    expect(controller.state!.incomeAvailable, isFalse);
    final persisted = await tester.runAsync(store.load);
    expect(persisted!.wallet, [130, 0, 0]);
    expect(persisted.goalId, 'garden');
    expect(persisted.completed, containsAll(['S01', 'B02', 'P01']));

    await tester.tap(find.byKey(const ValueKey('scene-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Раздел взрослого'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Раздел взрослого'));
    await tester.pumpAndSettle();
    final question = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .labelText!;
    final values = RegExp(
      r'\d+',
    ).allMatches(question).map((m) => int.parse(m.group(0)!)).toList();
    await tester.enterText(find.byType(TextField), '${values[0] + values[1]}');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    final remove = find.text('Удалить все данные');
    await tester.scrollUntilVisible(remove, 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 60 && controller.state!.name != null;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    await settleIo();
    expect(controller.state!.name, isNull);
    expect(find.text('Котёнок'), findsOneWidget);
    expect(find.text('Зачем эта игра'), findsNothing);
    expect(controller.state!.completed, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets(
    'Covered room pauses and rejects actions until its route becomes visible',
    (tester) async {
      final previous = WebViewPlatform.instance;
      final platform = _Platform();
      WebViewPlatform.instance = platform;
      addTearDown(() {
        if (previous != null) WebViewPlatform.instance = previous;
      });
      final navigator = GlobalKey<NavigatorState>();
      final room = GlobalKey<SharedRoomState>();
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: SharedRoom(
            key: room,
            sceneState: const {
              'mode': 'home',
              'room': 'living',
              'species': 'kitten',
            },
            soundEnabled: false,
            onAction: (_) async {
              actions++;
              return const SceneActionResult(true);
            },
          ),
        ),
      );
      for (var n = 0; n < 40 && room.currentState?.ready != true; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(room.currentState!.ready, true);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: SharedRoom(
            key: room,
            sceneState: const {
              'mode': 'home',
              'room': 'living',
              'species': 'kitten',
              'selectedJobId': 'J06',
            },
            soundEnabled: false,
            onAction: (_) async {
              actions++;
              return const SceneActionResult(true);
            },
          ),
        ),
      );
      await tester.pump();
      room.currentState!.updateViewportInsets(0, .32, 0, .32);
      platform.controller.scripts.clear();
      await room.currentState!.requestAction('job_j06');
      final synced = platform.controller.scripts.indexWhere(
        (script) =>
            script.contains('setState(') &&
            script.contains('"selectedJobId":"J06"') &&
            script.contains('"right":0.32') &&
            script.contains('"left":0.32'),
      );
      final launched = platform.controller.scripts.indexWhere(
        (script) => script.contains('requestAction("job_j06"'),
      );
      expect(synced, isNonNegative);
      expect(launched, greaterThan(synced));
      final selection =
          showModalBottomSheet<(String, String)>(
            context: room.currentContext!,
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(('single_book', 'living_shelf_high')),
              child: const Text('Выбрать верхнюю полку'),
            ),
          ).then((choice) async {
            if (choice != null) {
              await room.currentState!.placeJobItem(choice.$1, choice.$2);
            }
          });
      await tester.pumpAndSettle();
      expect(
        platform.controller.scripts.where((s) => s.contains('setPaused(')).last,
        contains('(true)'),
      );
      platform.controller.scripts.clear();
      await tester.tap(find.text('Выбрать верхнюю полку'));
      await tester.pumpAndSettle();
      await selection;
      final resumed = platform.controller.scripts.indexWhere(
        (s) => s.contains('setPaused(false)'),
      );
      final placed = platform.controller.scripts.indexWhere(
        (s) => s.contains(
          'placeJobItem({"sourceId":"single_book","targetId":"living_shelf_high"})',
        ),
      );
      expect(resumed, isNonNegative);
      expect(placed, greaterThan(resumed));
      final catalogReturn = navigator.currentState!
          .push<String>(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.pop(context, 'feed'),
                  child: const Text('Выбрать кормление'),
                ),
              ),
            ),
          )
          .then((action) async {
            if (action != null) await room.currentState!.showAction(action);
          });
      await tester.pumpAndSettle();
      platform.controller.scripts.clear();
      await tester.tap(find.text('Выбрать кормление'));
      await tester.pumpAndSettle();
      await catalogReturn;
      final guideResume = platform.controller.scripts.indexWhere(
        (script) => script.contains('setPaused(false)'),
      );
      final guidance = platform.controller.scripts.indexWhere(
        (script) => script.contains('showAction("feed")'),
      );
      expect(guideResume, isNonNegative);
      expect(guidance, greaterThan(guideResume));
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Preview')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        platform.controller.scripts.where((s) => s.contains('setPaused(')).last,
        contains('(true)'),
      );
      platform.controller.send({
        'type': 'action',
        'id': 'covered:1',
        'action': 'play',
        'room': 'living',
      });
      await tester.pump();
      expect(actions, 0);
      final count = platform.controller.scripts.length;
      await room.currentState!.requestAction('feed');
      await room.currentState!.placeJobItem('single_book', 'living_shelf_high');
      await room.currentState!.showAction('feed');
      expect(platform.controller.scripts.length, count);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        platform.controller.scripts.where((s) => s.contains('setPaused(')).last,
        contains('(false)'),
      );
      platform.controller.send({
        'type': 'action',
        'id': 'visible:1',
        'action': 'play',
        'room': 'living',
      });
      await tester.pumpAndSettle();
      expect(actions, 1);
      for (final removed in ['water', 'lamp']) {
        platform.controller.send({
          'type': 'action',
          'id': 'removed:$removed',
          'action': removed,
          'room': 'living',
        });
        await tester.pumpAndSettle();
        expect(actions, 1, reason: '$removed must not cross the bridge');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    },
  );
}
