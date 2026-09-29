import 'package:flutter/material.dart';
import 'game.dart';
import 'scene_bridge.dart';
import 'shared_room.dart';
import 'ui.dart';
import 'cartoon_props.dart';

/// Preview ownership is sent only to this disposable scene, never to the store.
Map<String, Object?> previewSceneState(
  GameState state, {
  String? itemId,
  String? goalId,
  bool removeWearable = false,
}) => {
  'mode': 'home',
  'room': goalId == 'garden' ? 'kitchen' : 'living',
  'species': ['kitten', 'puppy', 'hamster'][state.species],
  'color': 'fur_${(state.color % 3 + 1).toString().padLeft(2, '0')}',
  'stage': state.stage,
  'wearable': removeWearable
      ? null
      : {'cap', 'bow'}.contains(itemId)
      ? itemId
      : state.equippedWearable,
  'purchased': {...state.purchased, if (itemId != null) itemId}.toList(),
  'owned': {...state.owned, if (goalId != null) goalId}.toList(),
  'lampOn': itemId != 'nightlight' && goalId != 'stars',
  'starsOn': true,
  'nightlightOn': true,
  'adoptionOpen': true,
  'reducedMotion': state.reducedMotion,
  'busy': false,
  'jobsAllowed': false,
};

class ScenePreviewPage extends StatefulWidget {
  const ScenePreviewPage({
    super.key,
    required this.state,
    required this.title,
    required this.description,
    required this.priceLabel,
    this.itemId,
    this.goalId,
    this.removeWearable = false,
    this.confirmLabel,
    this.canConfirm = true,
  });
  final GameState state;
  final String title, description, priceLabel;
  final String? itemId, goalId, confirmLabel;
  final bool removeWearable, canConfirm;

  @override
  State<ScenePreviewPage> createState() => _ScenePreviewPageState();
}

class _ScenePreviewPageState extends State<ScenePreviewPage> {
  bool ready = false;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final large = media.textScaler.scale(1) >= 1.5;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: SharedRoom(
              sceneState: {
                ...previewSceneState(
                  widget.state,
                  itemId: widget.itemId,
                  goalId: widget.goalId,
                  removeWearable: widget.removeWearable,
                ),
                'reducedMotion':
                    widget.state.reducedMotion || media.disableAnimations,
              },
              onAction: (_) async => const SceneActionResult(false),
              soundEnabled: false,
              previewFramingFocus:
                  widget.goalId ??
                  switch (widget.itemId) {
                    'cozy_bed' => 'bed',
                    'ball' => 'ball',
                    'nightlight' => 'nightlight',
                    _ => 'pet',
                  },
              previewBottomFraction: large ? .58 : .42,
              onReadyChanged: (value) {
                if (mounted && ready != value) setState(() => ready = value);
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const CozyIcon(Icons.arrow_back_rounded),
                      label: const Text('Назад'),
                    ),
                  ),
                ),
                const Spacer(),
                Surface(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: media.size.height * (large ? .50 : .36),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ПРОСМОТР · БЕЗ ПОКУПКИ',
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(widget.description),
                          if (widget.itemId == 'stickers') ...[
                            const SizedBox(height: 12),
                            Semantics(
                              label:
                                  'Наклейки для страниц альбома: сердце, растение и звезда',
                              child: const ExcludeSemantics(
                                child: Wrap(
                                  spacing: 20,
                                  children: [
                                    PropArt(CartoonProp.heart, size: 44),
                                    PropArt(CartoonProp.garden, size: 44),
                                    PropArt(CartoonProp.lamp, size: 44),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            widget.priceLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          if (widget.confirmLabel != null)
                            FilledButton(
                              onPressed: ready && widget.canConfirm
                                  ? () => Navigator.pop(context, true)
                                  : null,
                              child: Text(widget.confirmLabel!),
                            ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              widget.confirmLabel == null
                                  ? 'Вернуться'
                                  : 'Передумаю',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
