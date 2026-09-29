import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/adult_page.dart';
import 'package:kopilych/album_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _ScenePlatform extends WebViewPlatform {
  late _SceneController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _SceneController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _SceneNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _SceneWidget(params);
}

class _SceneNavigation extends PlatformNavigationDelegate {
  _SceneNavigation(super.params) : super.implementation();
  PageEventCallback? onFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onFinished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _SceneController extends PlatformWebViewController {
  _SceneController(super.params) : super.implementation();
  JavaScriptChannelParams? channel;
  _SceneNavigation? navigation;
  String? lastIdentity;
  final scripts = <String>[];

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
    navigation = handler as _SceneNavigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    navigation?.onFinished?.call(params.uri.toString());
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    const prefix = 'window.KopilychScene?.setState(';
    if (!script.startsWith(prefix)) return;
    final state =
        jsonDecode(script.substring(prefix.length, script.length - 2))
            as Map<String, dynamic>;
    final identity = jsonEncode([
      state['mode'],
      state['species'],
      state['color'],
      state['adoptionOpen'],
    ]);
    if (identity == lastIdentity) return;
    lastIdentity = identity;
    await Future<void>.value();
    send({...state, 'mode': state['mode'] ?? 'home', 'type': 'ready'});
  }

  void send(Map<String, dynamic> message) => channel?.onMessageReceived(
    JavaScriptMessage(message: jsonEncode(message)),
  );
}

class _SceneWidget extends PlatformWebViewWidget {
  _SceneWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.green);
}

Future<void> _settle(WidgetTester tester, GameController controller) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    if (!controller.busy &&
        find.byType(SharedRoom).evaluate().isNotEmpty &&
        find
            .byType(SharedRoom)
            .evaluate()
            .every(
              (element) =>
                  element is StatefulElement &&
                  (element.state as SharedRoomState).ready,
            )) {
      return;
    }
  }
  fail(
    'Scene and SQLite did not become ready: busy=${controller.busy}, '
    'rooms=${find.byType(SharedRoom).evaluate().length}, '
    'home=${find.byType(GameHome).evaluate().length}',
  );
}

void main() {
  setUp(() {
    sqfliteFfiInit();
  });

  testWidgets('choosing a chore starts it after the picker closes', (
    tester,
  ) async {
    final previous = WebViewPlatform.instance;
    final platform = _ScenePlatform();
    WebViewPlatform.instance = platform;
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    tester.view.physicalSize = const Size(432, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = GameController(store);
    addTearDown(() async {
      controller.dispose();
      await tester.runAsync(store.close);
    });
    await tester.runAsync(() async {
      await controller.load();
      await controller.change('Ready for chores', (state) {
        state.name = 'Персик';
        state.setCurrentRoom('kitchen');
        state.confirmPlan([15, 10, 15]);
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller),
      ),
    );
    await _settle(tester, controller);

    await tester.tap(find.byKey(const ValueKey('scene-job')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-picker-j01')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('job-picker')), findsNothing);
    expect(
      platform.controller.scripts.any(
        (script) => script.contains('requestAction("job_j01"'),
      ),
      isTrue,
    );
  });

  testWidgets('home menu closes and each destination returns to the 3D home', (
    tester,
  ) async {
    final previous = WebViewPlatform.instance;
    WebViewPlatform.instance = _ScenePlatform();
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    tester.view.physicalSize = const Size(432, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = GameController(store);
    addTearDown(() async {
      controller.dispose();
      await tester.runAsync(store.close);
    });
    await tester.runAsync(() async {
      await controller.load();
      await controller.change('Adopt for route test', (state) {
        state.name = 'Пушок';
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: GameShell(controller: controller),
      ),
    );
    await _settle(tester, controller);

    Future<void> openMenu() async {
      await tester.tap(find.byKey(const ValueKey('scene-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Наш дом'), findsOneWidget);
    }

    await openMenu();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Наш дом'), findsNothing);
    expect(find.byType(GameHome), findsOneWidget);

    for (final destination in ['Бюджет', 'Задания', 'История']) {
      await openMenu();
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      expect(find.text('Наш дом'), findsNothing);
      expect(find.byKey(const ValueKey('back-to-home')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('back-to-home')));
      await _settle(tester, controller);
      expect(find.byType(GameHome), findsOneWidget);
    }

    await openMenu();
    await tester.tap(find.text('История').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Наш альбом'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsNothing);
    expect(find.byKey(const ValueKey('back-to-home')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-to-home')));
    await _settle(tester, controller);

    await openMenu();
    await tester.ensureVisible(find.text('Раздел взрослого'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Раздел взрослого'));
    await tester.pumpAndSettle();
    expect(find.byType(AdultGate), findsOneWidget);
    expect(find.text('Этот раздел — для взрослых'), findsOneWidget);
    expect(find.text('Наш дом'), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    await _settle(tester, controller);
    expect(find.byType(AdultGate), findsNothing);
    expect(find.byType(GameHome), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings opened from home menu persist after closing and reopening',
    (tester) async {
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = _ScenePlatform();
      addTearDown(() {
        if (previous != null) WebViewPlatform.instance = previous;
      });
      tester.view.physicalSize = const Size(432, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = GameController(store);
      addTearDown(() async {
        controller.dispose();
        await tester.runAsync(store.close);
      });
      await tester.runAsync(() async {
        await controller.load();
        await controller.change('Adopt for settings test', (state) {
          state.name = 'Пушок';
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller),
        ),
      );
      await _settle(tester, controller);

      Future<void> openSettings() async {
        await tester.tap(find.byKey(const ValueKey('scene-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Настройки'));
        await tester.pumpAndSettle();
        expect(find.text('Наш дом'), findsNothing);
        expect(find.text('Меньше движения'), findsOneWidget);
      }

      await openSettings();
      final motion = find.widgetWithText(SwitchListTile, 'Меньше движения');
      expect(controller.state!.reducedMotion, isFalse);
      await tester.tap(motion);
      await _settle(tester, controller);
      expect(controller.state!.reducedMotion, isTrue);
      await tester.binding.handlePopRoute();
      await _settle(tester, controller);
      expect(find.text('Меньше движения'), findsNothing);
      await openSettings();
      expect(tester.widget<SwitchListTile>(motion).value, isTrue);
      final saved = (await tester.runAsync(store.load))!;
      expect(saved.reducedMotion, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active dish round blocks home menu until the scene releases it',
    (tester) async {
      final previous = WebViewPlatform.instance;
      final platform = _ScenePlatform();
      WebViewPlatform.instance = platform;
      addTearDown(() {
        if (previous != null) WebViewPlatform.instance = previous;
      });
      tester.view.physicalSize = const Size(432, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = GameController(store);
      addTearDown(() async {
        controller.dispose();
        await tester.runAsync(store.close);
      });
      await tester.runAsync(() async {
        await controller.load();
        await controller.change('Adopt for dish route test', (state) {
          state.name = 'Пушок';
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller),
        ),
      );
      await _settle(tester, controller);

      void dish(String stage) => platform.controller.send({
        'type': 'minigame',
        'game': 'dishes',
        'stage': stage,
        'cleaned': stage == 'awaiting_ack' ? 6 : 0,
        'total': 6,
        'waterOn': stage == 'scrub',
      });

      for (final stage in ['scrub', 'awaiting_ack']) {
        dish(stage);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('scene-menu')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('scene-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Наш дом'), findsNothing);
      }
      dish('idle');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scene-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Наш дом'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
