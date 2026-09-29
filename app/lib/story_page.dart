import 'package:flutter/material.dart';
import 'art.dart';
import 'cartoon_props.dart';
import 'dialogue_page.dart';
import 'game.dart';
import 'story.dart';
import 'story_dialogue.dart';
import 'ui.dart';

class StoryPage extends StatelessWidget {
  const StoryPage({
    super.key,
    required this.state,
    required this.onGo,
    required this.onCelebrate,
  });

  final GameState state;
  final void Function(String) onGo;
  final VoidCallback onCelebrate;

  @override
  Widget build(BuildContext context) {
    final chapters = storyChapters(state);
    final current = currentChapter(state);
    final intro = firstDayGuide(state);
    final active = intro ?? storyActiveTask(state);
    final chapter = current < chapters.length ? chapters[current] : null;
    final friend = state.name?.trim().isNotEmpty == true
        ? state.name!.trim()
        : 'Твой друг';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Heading(
          'Дом маленьких мечт',
          subtitle: 'Одна понятная задача — один следующий шаг.',
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/art/story-choice-hamster-meshy.png',
            semanticLabel:
                'Хомячок и котёнок выбирают у прилавка: монетки и два конверта',
          ),
        ),
        const SizedBox(height: 18),
        Surface(
          color: sage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current == chapters.length
                    ? 'История новоселья пройдена'
                    : 'Глава ${current + 1} из ${chapters.length}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '$friend, три конверта и дом, который становится уютнее вместе с вами.',
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: current / chapters.length,
                minHeight: 7,
                color: blue,
                backgroundColor: cream,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => onGo('album'),
          icon: const CozyIcon(Icons.photo_album_outlined),
          label: const Text('Наш альбом'),
        ),
        const SizedBox(height: 14),
        if (chapter != null && active != null)
          Surface(
            color: const Color(0xFFF0E6CB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PropArt(CartoonProp.values[chapter.prop], size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        chapter.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const CozyIcon(Icons.auto_stories_rounded, color: blue),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  intro == null
                      ? chapter.scene
                      : 'Осмотрим дом вместе. Один шаг за раз: игра, еда, чистота, заказ и мечта.',
                ),
                const SizedBox(height: 16),
                if (intro == null)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (sceneContext) => DialoguePage(
                          state: state,
                          voiceEnabled: state.voiceEnabled,
                          chapter: current,
                          sceneOverride: canonicalDialogueScenes[current],
                          hintOverride: canonicalDialogueHints[current],
                          onContinue: () {
                            Navigator.of(sceneContext).pop();
                            onGo(active.target);
                          },
                        ),
                      ),
                    ),
                    icon: const CozyIcon(Icons.record_voice_over_rounded),
                    label: const Text('Поговорить с питомцем'),
                  ),
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  label: 'Текущая задача: ${active.label}',
                  child: Surface(
                    color: sage,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Сейчас',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          active.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => onGo(active.target),
                          child: Text(active.label),
                        ),
                        if (active.secondaryTarget != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => onGo(active.secondaryTarget!),
                            child: Text(active.secondaryLabel!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (current > 0 && current < chapters.length) ...[
          const SizedBox(height: 12),
          Text(
            'Пройдено глав: $current. Следующие шаги откроются по одному.',
            style: const TextStyle(color: muted, fontSize: 14),
          ),
        ],
        if (current == chapters.length) ...[
          Surface(
            color: const Color(0xFFF0E6CB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapters.last.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(chapters.last.ending),
              ],
            ),
          ),
          SizedBox(
            height: 230,
            child: PetScene(
              species: state.species,
              color: state.color,
              accessory: state.visibleAccessory,
              room: false,
              stage: state.stage,
              reducedMotion: state.reducedMotion,
            ),
          ),
          FilledButton.icon(
            onPressed: onCelebrate,
            icon: const CozyIcon(Icons.celebration_outlined),
            label: const Text('Праздновать дома'),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'История сама не списывает и не начисляет монеты. '
          'Каждый результат сохраняется только в соответствующем игровом действии.',
          style: TextStyle(color: muted, fontSize: 14),
        ),
      ],
    );
  }
}
