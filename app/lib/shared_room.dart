import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'local_scene_server.dart';
import 'scene_bridge.dart';
import 'ui.dart';

class SharedRoom extends StatefulWidget {
  const SharedRoom({
    super.key,
    required this.sceneState,
    required this.onAction,
    required this.soundEnabled,
    this.soundVolume = 100,
    this.graphicsQuality = 'auto',
    this.onReadyChanged,
    this.onDishChanged,
    this.onJobChanged,
    this.paused = false,
    this.dialogueFraming = 0,
    this.previewFramingFocus,
    this.previewBottomFraction = .42,
  });

  final Map<String, Object?> sceneState;
  final Future<SceneActionResult> Function(SceneAction) onAction;
  final bool soundEnabled;
  final int soundVolume;
  final String graphicsQuality;
  final ValueChanged<bool>? onReadyChanged;
  final ValueChanged<DishProgress>? onDishChanged;
  final ValueChanged<JobProgress>? onJobChanged;
  final bool paused;
  final double dialogueFraming;
  final String? previewFramingFocus;
  final double previewBottomFraction;

  @override
  State<SharedRoom> createState() => SharedRoomState();
}

class SharedRoomState extends State<SharedRoom> with WidgetsBindingObserver {
  final _server = LocalSceneServer();
  final _resolved = <String, Map<String, Object?>>{};
  WebViewController? _web;
  bool ready = false,
      _pageLoaded = false,
      _background = false,
      _routeVisible = true,
      _hasRenderedScene = false;
  String? _pending, _error;
  int _visualGeneration = 0;
  Timer? _loadDeadline;
  Map<String, dynamic> diagnostics = {};
  String? lastReadyRoom,
      lastReadySpecies,
      lastReadyColor,
      lastContactAction,
      lastGuidanceAction;
  DishProgress dish = const DishProgress();
  JobProgress job = const JobProgress();
  Map<String, double> _viewInsets = {
    'top': 0,
    'right': 0,
    'bottom': 0,
    'left': 0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (_routeVisible != visible) {
      _routeVisible = visible;
      unawaited(_sync());
    }
  }

  Future<void> _open() async {
    try {
      await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      final web = WebViewController();
      if (web.platform is AndroidWebViewController) {
        // Debugging is available only in development builds.
        await AndroidWebViewController.enableDebugging(kDebugMode);
      }
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setBackgroundColor(cream);
      await web.enableZoom(false);
      await web.addJavaScriptChannel(
        'KopilychBridge',
        onMessageReceived: (message) => unawaited(_message(message.message)),
      );
      await web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _server.owns(Uri.parse(request.url))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            _pageLoaded = true;
            unawaited(_sync());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _fail('Комната не открылась. Попробуем ещё раз.');
            }
          },
        ),
      );
      _web = web;
      if (!mounted) return;
      setState(() {});
      _startDeadline();
      await web.loadRequest(_server.index);
    } catch (error) {
      if (kDebugMode) debugPrint('Scene startup: $error');
      _fail('Не удалось открыть комнату. Прогресс сохранён.');
    }
  }

  void _startDeadline() {
    _loadDeadline?.cancel();
    _loadDeadline = Timer(const Duration(seconds: 50), () {
      if (!ready) _fail('Комната загружается слишком долго. Попробуем снова.');
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    _loadDeadline?.cancel();
    setState(() {
      ready = false;
      _error = message;
    });
    widget.onReadyChanged?.call(false);
  }

  bool _matchesVisualState(Map<String, dynamic> message) {
    for (final key in [
      'mode',
      'room',
      'species',
      'color',
      'wearable',
      'adoptionOpen',
    ]) {
      if (widget.sceneState.containsKey(key) &&
          message[key] != widget.sceneState[key]) {
        return false;
      }
    }
    return true;
  }

  void _acceptReady(Map<String, dynamic> message) {
    lastReadyRoom = message['room'] as String?;
    lastReadySpecies = message['species'] is String
        ? message['species'] as String
        : null;
    lastReadyColor = message['color'] is String
        ? message['color'] as String
        : null;
    if (!_matchesVisualState(message)) return;
    _loadDeadline?.cancel();
    final notify = !ready;
    setState(() {
      ready = true;
      _hasRenderedScene = true;
      _error = null;
    });
    if (notify) widget.onReadyChanged?.call(true);
  }

  Future<void> _message(String raw) async {
    if (!mounted) return;
    final message = readSceneMessage(raw);
    if (message == null) return;
    switch (message['type']) {
      case 'minigame':
        final progress = DishProgress.parse(message);
        if (progress != null) {
          setState(() => dish = progress);
          widget.onDishChanged?.call(progress);
          return;
        }
        final jobProgress = JobProgress.parse(message);
        if (jobProgress == null) return;
        setState(() => job = jobProgress);
        widget.onJobChanged?.call(jobProgress);
      case 'ready':
        diagnostics = message;
        _acceptReady(message);
        await _sync();
      case 'diagnostic':
        diagnostics = message;
        if (message['code'] == 'SCENE_READY') {
          _acceptReady(message);
        }
        if (message['code'] == 'ACTION_CONTACT_COMPLETE') {
          lastContactAction = message['action'] as String?;
        }
        if (message['code'] == 'GUIDANCE_TARGET_SHOWN') {
          lastGuidanceAction = message['action'] as String?;
        }
      case 'error':
        if (kDebugMode) {
          debugPrint('3D scene: ${message['code']} ${message['message']}');
        }
        _fail('Не удалось показать комнату. Попробуем открыть её снова.');
      case 'action':
        final action = SceneAction.parse(message);
        if (action == null) return;
        final previous = _resolved[action.id];
        if (previous != null) {
          await _call('resolveAction', previous);
          return;
        }
        if (_pending == action.id) return;
        if (_pending != null ||
            widget.paused ||
            _background ||
            !_routeVisible) {
          await _call(
            'resolveAction',
            const SceneActionResult(
              false,
              message: 'Подожди немного.',
            ).acknowledgement(action.id),
          );
          return;
        }
        _pending = action.id;
        SceneActionResult result;
        try {
          result = await widget.onAction(action);
        } catch (_) {
          result = const SceneActionResult(
            false,
            message: 'Не получилось подтвердить действие. Проверим сохранение.',
          );
        } finally {
          _pending = null;
        }
        final ack = result.acknowledgement(action.id);
        _resolved[action.id] = ack;
        if (_resolved.length > 256) _resolved.remove(_resolved.keys.first);
        if (mounted) await _call('resolveAction', ack);
    }
  }

  Future<void> _call(String method, Object? argument) async {
    final web = _web;
    if (web == null || !_pageLoaded || !mounted) return;
    try {
      await web.runJavaScript(
        'window.KopilychScene?.$method(${jsonEncode(argument)});',
      );
    } catch (error) {
      if (mounted && kDebugMode) debugPrint('Scene bridge: $error');
    }
  }

  Future<void> _sync() async {
    await _call('setState', {
      ...widget.sceneState,
      'viewportInsets': _viewInsets,
    });
    await _call('setSoundEnabled', widget.soundEnabled);
    await _call('setSoundVolume', widget.soundVolume);
    await _call('setGraphicsQuality', widget.graphicsQuality);
    await _call('setPaused', widget.paused || _background || !_routeVisible);
    if (widget.dialogueFraming > 0 &&
        !widget.paused &&
        !_background &&
        _routeVisible) {
      await _call('setDialogueFraming', widget.dialogueFraming);
    }
    if (widget.previewFramingFocus != null &&
        !widget.paused &&
        !_background &&
        _routeVisible) {
      await _call(
        'setPreviewFraming',
        widget.previewFramingFocus == null
            ? false
            : {
                'focus': widget.previewFramingFocus,
                'bottomFraction': widget.previewBottomFraction,
              },
      );
    }
  }

  void updateViewportInsets(
    double top,
    double right,
    double bottom,
    double left,
  ) {
    if (_viewInsets['top'] == top &&
        _viewInsets['right'] == right &&
        _viewInsets['bottom'] == bottom &&
        _viewInsets['left'] == left) {
      return;
    }
    _viewInsets = {'top': top, 'right': right, 'bottom': bottom, 'left': left};
    unawaited(_sync());
  }

  Future<void> dishStep(String step) => _call('dishStep', step);
  Future<void> cancelDishGame() => _call('cancelDishGame', null);
  Future<void> jobStep(String step) => _call('jobStep', step);
  Future<void> placeJobItem(String sourceId, String targetId) async {
    if (!mounted || !ready || widget.paused || _background) return;
    // The choice sheet pauses the covered room. Restore visibility and flush
    // the resume before sending its choice; route dependencies rebuild later.
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_routeVisible) return;
    await _sync();
    if (!mounted || widget.paused || _background || !_routeVisible) return;
    await _call('placeJobItem', {'sourceId': sourceId, 'targetId': targetId});
  }

  Future<void> cancelJobGame() => _call('cancelJobGame', null);

  Future<void> playReaction(String kind, {required int serial}) async {
    if (!{'listen', 'look', 'happy'}.contains(kind) ||
        !ready ||
        !_routeVisible ||
        widget.paused ||
        _background) {
      return;
    }
    await _sync();
    await _call('playReaction', {'kind': kind, 'serial': serial});
  }

  Future<void> playCue(String cue) async {
    if (!{
      'uiTap',
      'uiBack',
      'uiConfirm',
      'uiReward',
      'coinSave',
      'clothFold',
      'clothPlace',
      'dishPlace',
      'boxLid',
      'boxPop',
      'waterRinse',
      'broomSweep',
    }.contains(cue)) {
      return;
    }
    await _call('playAudioCue', cue);
  }

  Future<void> showAction(String action) async {
    if (!{
          'feed',
          'water',
          'play',
          'clean',
          'wash_dishes',
          'job_j01',
          'job_j02',
          'job_j03',
          'job_j04',
          'job_j05',
          'job_j06',
        }.contains(action) ||
        !mounted ||
        !ready ||
        _pending != null ||
        widget.paused ||
        _background) {
      return;
    }
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_routeVisible) return;
    await _sync();
    if (!mounted || widget.paused || _background || !_routeVisible) return;
    await _call('showAction', action);
  }

  Future<void> requestAction(String action, {String? targetRoom}) async {
    if (!mounted ||
        !ready ||
        (_pending != null && action != 'room') ||
        widget.paused ||
        _background ||
        !_routeVisible) {
      return;
    }
    final web = _web;
    if (web == null) return;
    try {
      // Flush Flutter-owned selection/period state before the runtime starts a
      // round, so a fast tap cannot launch with the previous job metadata.
      await _sync();
      await web.runJavaScript(
        'window.KopilychScene?.requestAction(${jsonEncode(action)},${jsonEncode(targetRoom)});',
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Scene action: $error');
      _fail('Комната ещё не готова. Откроем её снова.');
    }
  }

  Future<void> retry() async {
    if (_pending != null || _web == null) return;
    setState(() {
      ready = false;
      _error = null;
      _pageLoaded = false;
      _hasRenderedScene = false;
      dish = const DishProgress();
      job = const JobProgress();
    });
    widget.onDishChanged?.call(dish);
    widget.onJobChanged?.call(job);
    widget.onReadyChanged?.call(false);
    _startDeadline();
    try {
      await _web!.reload();
    } catch (error) {
      if (kDebugMode) debugPrint('Scene reload: $error');
      _fail('Не удалось открыть комнату. Прогресс сохранён.');
    }
  }

  @override
  void didUpdateWidget(SharedRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewFramingFocus != null &&
        widget.previewFramingFocus == null) {
      unawaited(_call('setPreviewFraming', false));
    }
    final visualIdentityChanged = [
      'mode',
      'species',
      'color',
      'wearable',
      'adoptionOpen',
    ].any((key) => oldWidget.sceneState[key] != widget.sceneState[key]);
    if (visualIdentityChanged && ready) {
      ready = false;
      final generation = ++_visualGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _visualGeneration && !ready) {
          widget.onReadyChanged?.call(false);
        }
      });
    }
    unawaited(_sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    unawaited(_sync());
  }

  @override
  void didChangeMetrics() {
    // Android can resize the Flutter view before WebView sends its own resize
    // event. Refresh the WebGL drawing buffer after the new frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageLoaded) return;
      unawaited(
        _web?.runJavaScript(
          'requestAnimationFrame(() => window.dispatchEvent(new Event("resize")));',
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadDeadline?.cancel();
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _call('disposeAudio', null);
    await _server.close();
  }

  Widget _sceneWebView(BuildContext context) {
    final recognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(
        () => dish.active || job.active
            ? EagerGestureRecognizer()
            : TapGestureRecognizer(),
      ),
    };
    final params = PlatformWebViewWidgetCreationParams(
      controller: _web!.platform,
      gestureRecognizers: recognizers,
    );
    // Ключ по ориентации пересоздавал WebView при повороте и обрывал мини-игру;
    // размер обновляется через didChangeMetrics → JS resize.
    return WebViewWidget.fromPlatformCreationParams(
      params: WebViewPlatform.instance is AndroidWebViewPlatform
          ? AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
              params,
              displayWithHybridComposition: true,
            )
          : params,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dish.active && !job.active,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && dish.active && dish.stage != 'awaiting_ack') {
        unawaited(cancelDishGame());
      }
      if (!didPop && job.active && job.stage != 'awaiting_ack') {
        unawaited(cancelJobGame());
      }
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (_web != null) _sceneWebView(context),
        if (!_hasRenderedScene || _error != null)
          ColoredBox(
            color: cream,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error == null) const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _error ?? 'Открываем наш дом…',
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: retry,
                        icon: const CozyIcon(Icons.refresh_rounded),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
