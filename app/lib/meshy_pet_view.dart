import 'dart:async';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'pet_motion.dart';

enum PetAnimation {
  idle,
  walk,
  feed,
  play,
  bath,
  happy;

  static PetAnimation fromAction(PetAction action) => switch (action) {
    PetAction.feed => feed,
    PetAction.play => play,
    PetAction.bath => bath,
    PetAction.love || PetAction.celebrate => happy,
    PetAction.idle => idle,
  };
}

/// Renders the optimized, original Meshy pet mesh inside the Android scene.
class MeshyPetView extends StatefulWidget {
  const MeshyPetView({
    super.key,
    required this.species,
    this.interactive = true,
    this.wearable,
    this.animation = PetAnimation.idle,
    this.animationEvent = 0,
    this.reducedMotion = false,
    this.animationEnabled = false,
  });

  final int species;
  final bool interactive;
  final String? wearable;
  final PetAnimation animation;

  /// Increment to replay an animation, including two consecutive care actions.
  final int animationEvent;
  final bool reducedMotion;
  // The experimental deform rig was rejected after visual review. Keep the
  // legacy Meshy model static until the shared room renderer replaces it.
  final bool animationEnabled;

  @override
  State<MeshyPetView> createState() => _MeshyPetViewState();

  static const assets = [
    'assets/models/kitten-mobile.glb',
    'assets/models/puppy-mobile.glb',
    'assets/models/hamster-mobile.glb',
  ];

  static String assetFor(int species, String? wearable) {
    if (species < 0 || species >= assets.length) {
      throw RangeError.index(species, assets);
    }
    if (wearable == null) return assets[species];
    if (wearable != 'cap' && wearable != 'bow') {
      throw ArgumentError.value(wearable, 'wearable');
    }
    // 29.09: облегчение APK — предпросмотр аксессуара показывает базовую модель.
    return assets[species];
  }
}

class _MeshyPetViewState extends State<MeshyPetView> {
  static const reactionDuration = Duration(milliseconds: 2400);
  Timer? _returnToIdle;
  Future<void> Function(String)? _runJavaScript;
  bool _modelReady = false;
  bool? _lastStill;
  PetAnimation _activeAnimation = PetAnimation.idle;

  bool get _still =>
      widget.reducedMotion || MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = _still;
    if (_lastStill != null && still != _lastStill) _applyAnimation();
    _lastStill = still;
  }

  @override
  void didUpdateWidget(covariant MeshyPetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MeshyPetView.assetFor(oldWidget.species, oldWidget.wearable) !=
        MeshyPetView.assetFor(widget.species, widget.wearable)) {
      _modelReady = false;
      _runJavaScript = null;
    }
    if (widget.animationEvent != oldWidget.animationEvent) {
      _returnToIdle?.cancel();
      _activeAnimation = widget.animation;
      _applyAnimation();
      if (_activeAnimation != PetAnimation.idle) {
        _returnToIdle = Timer(reactionDuration, () {
          if (!mounted) return;
          _activeAnimation = PetAnimation.idle;
          _applyAnimation();
        });
      }
    } else if (widget.reducedMotion != oldWidget.reducedMotion) {
      _applyAnimation();
    }
  }

  void _applyAnimation() {
    if (!widget.animationEnabled) return;
    if (!_modelReady || _runJavaScript == null) return;
    final clip = _activeAnimation.name;
    final still = _still;
    // Clip names are fixed enum values, so they cannot inject arbitrary JS.
    unawaited(
      _sendAnimation('''
      (() => {
        const model = document.querySelector('model-viewer');
        if (!model) return;
        const available = model.availableAnimations || [];
        const selected = available.includes('$clip')
          ? '$clip'
          : available.includes('idle')
            ? 'idle'
            : available[0];
        if (!selected) return;
        model.pause();
        model.animationName = selected;
        model.currentTime = ${still && _activeAnimation != PetAnimation.idle ? '0.35' : '0'};
        if (${!still}) model.play();
      })();
    '''),
    );
  }

  Future<void> _sendAnimation(String script) async {
    try {
      await _runJavaScript?.call(script);
    } catch (_) {
      // A disposed or reloading WebView can reject the last queued update.
    }
  }

  @override
  void dispose() {
    _returnToIdle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModelViewer(
    key: ValueKey(MeshyPetView.assetFor(widget.species, widget.wearable)),
    src: MeshyPetView.assetFor(widget.species, widget.wearable),
    alt:
        '${['Котёнок', 'Щенок', 'Хомячок'][widget.species]}${widget.wearable == null
            ? ''
            : widget.wearable == 'cap'
            ? ' в шапочке'
            : ' с бантиком'}',
    ar: false,
    // The first shipped GLBs contain only a single legacy idle track. The
    // WebView chooses the requested clip when it exists and falls back safely.
    autoPlay: widget.animationEnabled && !_still,
    animationCrossfadeDuration: 150,
    autoRotate: false,
    cameraControls: widget.interactive,
    disableZoom: true,
    interactionPrompt: InteractionPrompt.none,
    cameraOrbit: '0deg 75deg auto',
    fieldOfView: '32deg',
    shadowIntensity: 0,
    backgroundColor: Colors.transparent,
    relatedCss:
        'html, body { background: transparent !important; } '
        'model-viewer { --poster-color: transparent; }',
    relatedJs: '''
      document.querySelector('model-viewer').addEventListener('load', () => {
        PetModelReady.postMessage('ready');
      });
    ''',
    javascriptChannels: {
      JavascriptChannel(
        'PetModelReady',
        onMessageReceived: (_) {
          if (!mounted) return;
          _modelReady = true;
          _applyAnimation();
        },
      ),
    },
    onWebViewCreated: (controller) {
      _runJavaScript = controller.runJavaScript;
    },
  );
}

/// Opens the actual Meshy care prop from the corresponding room.
class MeshyPropView extends StatelessWidget {
  const MeshyPropView({super.key, required this.roomIndex});

  final int roomIndex;

  static const assets = [
    'assets/models/bed-mobile.glb',
    'assets/models/food_bowl-mobile.glb',
    'assets/models/bathtub-mobile.glb',
  ];
  static const labels = ['Лежанка', 'Миска', 'Ванна'];

  @override
  Widget build(BuildContext context) => ModelViewer(
    key: ValueKey(roomIndex),
    src: assets[roomIndex],
    alt: labels[roomIndex],
    ar: false,
    autoRotate: true,
    cameraControls: true,
    disableZoom: true,
    interactionPrompt: InteractionPrompt.none,
    shadowIntensity: 0,
    backgroundColor: Colors.transparent,
    relatedCss:
        'html, body { background: transparent !important; } '
        'model-viewer { --poster-color: transparent; }',
  );
}
