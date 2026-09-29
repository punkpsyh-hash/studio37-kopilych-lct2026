import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/game_home.dart';
import 'package:kopilych/shared_room.dart';
import 'package:kopilych/shell.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _RotationWebViewPlatform extends WebViewPlatform {
  late _RotationWebViewController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _RotationWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _RotationNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _RotationWebViewWidget(params);
}

class _RotationNavigationDelegate extends PlatformNavigationDelegate {
  _RotationNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? _onFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    _onFinished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _RotationWebViewController extends PlatformWebViewController {
  _RotationWebViewController(super.params) : super.implementation();

  JavaScriptChannelParams? _channel;
  _RotationNavigationDelegate? _navigation;
  String? _lastIdentity;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    _channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigation = handler as _RotationNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    _navigation?._onFinished?.call(params.uri.toString());
  }

  @override
  Future<void> runJavaScript(String script) async {
    const marker = 'window.KopilychScene?.setState(';
    if (!script.startsWith(marker)) return;
    final state =
        jsonDecode(script.substring(marker.length, script.length - 2))
            as Map<String, dynamic>;
    final identity = jsonEncode([
      state['mode'],
      state['species'],
      state['color'],
      state['adoptionOpen'],
    ]);
    if (identity == _lastIdentity) return;
    _lastIdentity = identity;
    await Future<void>.value();
    _channel?.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode({
          ...state,
          'mode': state['mode'] ?? 'home',
          'type': 'ready',
        }),
      ),
    );
  }
}

class _RotationWebViewWidget extends PlatformWebViewWidget {
  _RotationWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.green);
}

void main() {
  testWidgets(
    'portrait-landscape rotation keeps home save, selected pet and accessible HUD',
    (tester) async {
      final previousPlatform = WebViewPlatform.instance;
      WebViewPlatform.instance = _RotationWebViewPlatform();
      addTearDown(() {
        if (previousPlatform != null) {
          WebViewPlatform.instance = previousPlatform;
        }
      });
      tester.view.physicalSize = const Size(432, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => GameStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.runAsync(
        () => store.change('orientation-fixture', 'Rotation fixture', (state) {
          state.name = 'Искорка';
          state.species = 2;
          state.setCurrentRoom('bathroom');
          state.wallet = [73, 41, 16];
          state.day = 3;
          state.completed.add('canon:S01:3');
        }),
      );
      final controller = GameController(store);
      addTearDown(controller.dispose);
      await tester.runAsync(controller.load);

      Future<void> settleRoom() async {
        for (var attempt = 0; attempt < 60; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          final rooms = find.byType(SharedRoom).evaluate();
          if (!controller.busy &&
              rooms.any(
                (element) =>
                    element is StatefulElement &&
                    element.state is SharedRoomState &&
                    (element.state as SharedRoomState).ready,
              )) {
            return;
          }
        }
        fail('Controlled scene bridge and save should settle');
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: GameShell(controller: controller),
        ),
      );
      await settleRoom();

      void expectSavedHome() {
        final saved = controller.state!;
        expect(saved.currentRoom, 'bathroom');
        expect(saved.species, 2);
        expect(saved.name, 'Искорка');
        expect(saved.wallet, [73, 41, 16]);
        expect(saved.day, 3);
        expect(saved.completed, contains('canon:S01:3'));
        expect(find.byType(GameHome), findsOneWidget);
        expect(find.textContaining('Искорка'), findsOneWidget);
      }

      expectSavedHome();
      await tester.binding.setSurfaceSize(const Size(850, 432));
      await tester.pumpAndSettle();
      expectSavedHome();
      expect(
        find.byKey(const ValueKey('scene-landscape-status')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(432, 850));
      await tester.pumpAndSettle();
      expectSavedHome();
      final persisted = await tester.runAsync(store.load);
      expect(persisted!.currentRoom, 'bathroom');
      expect(persisted.species, 2);
      expect(persisted.wallet, [73, 41, 16]);
      expect(persisted.completed, contains('canon:S01:3'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
}
