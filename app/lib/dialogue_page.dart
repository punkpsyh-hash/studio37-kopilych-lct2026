import 'dart:async';
import 'package:flutter/material.dart';
import 'game.dart';
import 'local_voice.dart';
import 'scene_bridge.dart';
import 'shared_room.dart';
import 'story_dialogue.dart';
import 'ui.dart';

class DialoguePage extends StatefulWidget {
  const DialoguePage({
    super.key,
    required this.state,
    required this.chapter,
    required this.onContinue,
    this.sceneOverride,
    this.hintOverride,
    this.voiceFactory,
    this.voiceEnabled = true,
  });
  final GameState state;
  final int chapter;
  final VoidCallback onContinue;
  final DialogueScene? sceneOverride;
  final String? hintOverride;
  final VoiceSession Function()? voiceFactory;
  final bool voiceEnabled;
  @override
  State<DialoguePage> createState() => _DialoguePageState();
}

class _DialoguePageState extends State<DialoguePage>
    with WidgetsBindingObserver {
  VoiceSession? voice;
  final roomKey = GlobalKey<SharedRoomState>();
  final dialogueScroll = ScrollController();
  String reactionKind = 'look';
  int line = 0, reaction = 0;
  int? chosen, pending;
  String transcript = '', notice = '';
  bool sound = false, help = false;
  DialogueScene get scene =>
      widget.sceneOverride ?? dialogueScenes[widget.chapter];
  String get hint => widget.hintOverride ?? dialogueHints[widget.chapter];
  bool get atChoice => line == scene.lines.length - 1 && chosen == null;
  String get spokenText => help
      ? hint
      : chosen == null
      ? scene.lines[line]
      : scene.choices[chosen!].reply;
  String? get spokenClipId {
    if (widget.sceneOverride != null) return null;
    final chapter = (widget.chapter + 1).toString().padLeft(2, '0');
    if (help) return 'chapter_$chapter.hint';
    if (chosen != null) {
      final choice = (chosen! + 1).toString().padLeft(2, '0');
      return 'chapter_$chapter.choice_$choice.reply';
    }
    final utterance = (line + 1).toString().padLeft(2, '0');
    return 'chapter_$chapter.line_$utterance';
  }

  VoiceSession get speech =>
      voice ??= ((widget.voiceFactory?.call() ?? LocalVoice())
        ..addListener(refresh));
  void refresh() {
    if (mounted) setState(() {});
  }

  void showReaction(String kind) {
    reactionKind = kind;
    reaction++;
    unawaited(roomKey.currentState?.playReaction(kind, serial: reaction));
  }

  void showReplyStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && dialogueScroll.hasClients) dialogueScroll.jumpTo(0);
    });
  }

  @override
  void initState() {
    super.initState();
    sound = widget.voiceEnabled;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showReaction('look');
        unawaited(say());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive &&
            ((voice?.listening ?? false) || (voice?.speaking ?? false)))) {
      sound = false;
      unawaited(voice?.stop());
    }
  }

  Future<void> say() async {
    if (!widget.voiceEnabled) return;
    setState(() {
      sound = true;
      notice = '';
    });
    try {
      await speech.say(spokenText, clipId: spokenClipId);
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Не получилось включить голос. Реплика доступна на экране.',
        );
      }
    }
  }

  Future<void> advance() async {
    await voice?.stop();
    if (!mounted) return;
    setState(() {
      line++;
      help = false;
      transcript = notice = '';
      pending = null;
    });
    showReaction('look');
    showReplyStart();
    if (sound) await say();
  }

  Future<void> choose(int index) async {
    await voice?.stop();
    if (!mounted) return;
    setState(() {
      chosen = index;
      pending = null;
      help = false;
      notice = '';
    });
    showReaction('happy');
    showReplyStart();
    if (sound) await say();
  }

  Future<void> listen() async {
    if (voice?.listening ?? false) {
      await finish();
      return;
    }
    setState(() {
      notice = transcript = '';
      pending = null;
      help = false;
    });
    showReaction('listen');
    try {
      await speech.startListening(() => unawaited(finish()));
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Не удалось включить микрофон. Проверь разрешение или выбери ответ кнопкой.',
        );
      }
    }
  }

  Future<void> finish() async {
    try {
      final text = await speech.finishListening();
      if (!mounted || chosen != null) return;
      setState(() {
        transcript = text;
        pending = matchDialogueChoice(text, scene.choices);
        if (text.toLowerCase().contains('объясни') ||
            text.toLowerCase().contains('помоги')) {
          help = true;
          pending = null;
        } else if (pending == null) {
          notice = text.isEmpty
              ? 'Не расслышал. Попробуй ещё раз или нажми на ответ.'
              : 'Проверь фразу. Можно сказать «первый вариант», «второй вариант» или выбрать кнопкой.';
        }
      });
      showReplyStart();
      if (help && sound) await say();
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Не удалось разобрать речь. Можно повторить или ответить кнопкой.',
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voice?.removeListener(refresh);
    voice?.dispose();
    dialogueScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = voice?.busy ?? false, listening = voice?.listening ?? false;
    final state = widget.state;
    final enlargedText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) => Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label:
                  '${state.name ?? "Твой друг"}: ${listening ? "слушает" : "рядом с тобой"}',
              child: IgnorePointer(
                child: SharedRoom(
                  key: roomKey,
                  dialogueFraming:
                      ((enlargedText ? .64 : .52) +
                              (MediaQuery.paddingOf(context).bottom + 12) /
                                  bounds.maxHeight)
                          .clamp(0.0, .7),
                  sceneState: {
                    'mode': 'home',
                    'room': state.currentRoom,
                    'species': ['kitten', 'puppy', 'hamster'][state.species],
                    'color':
                        'fur_${(state.color % 3 + 1).toString().padLeft(2, '0')}',
                    'wearable': state.equippedWearable,
                    'stage': state.stage,
                    'owned': state.owned.toList(),
                    'purchased': state.purchased.toList(),
                    'lampOn': state.currentLampOn,
                    'starsOn': state.starsOn,
                    'nightlightOn': state.nightlightOn,
                    'reducedMotion':
                        state.reducedMotion ||
                        MediaQuery.disableAnimationsOf(context),
                    'busy': false,
                    'jobsAllowed': false,
                    'jobPeriod': state.day,
                  },
                  onAction: (_) async => const SceneActionResult(false),
                  soundEnabled: false,
                  onReadyChanged: (ready) {
                    if (ready) {
                      unawaited(
                        roomKey.currentState?.playReaction(
                          reactionKind,
                          serial: reaction,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Material(
                          color: cream,
                          shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFFE0C9A5)),
                          ),
                          child: CozyBackButton(
                            onPressed: () => Navigator.maybePop(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Surface(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Text(
                              'Глава ${widget.chapter + 1} · разговор',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 620,
                        maxHeight:
                            bounds.maxHeight * (enlargedText ? .64 : .52),
                      ),
                      child: Surface(
                        padding: const EdgeInsets.all(16),
                        child: ListView(
                          controller: dialogueScroll,
                          key: const ValueKey('dialogue-panel'),
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            Text(
                              scene.setting,
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              scene.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 10),
                            Surface(
                              color: sage,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.state.name ?? 'Твой друг',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      spokenText,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton.icon(
                                        onPressed:
                                            !widget.voiceEnabled ||
                                                busy ||
                                                listening
                                            ? null
                                            : say,
                                        icon: const CozyIcon(
                                          Icons.volume_up_rounded,
                                        ),
                                        label: const Text('Послушать'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await voice?.stop();
                                          if (!mounted) return;
                                          setState(() => help = !help);
                                          showReplyStart();
                                          if (sound) await say();
                                        },
                                        child: Text(
                                          help ? 'К реплике' : 'Объясни проще',
                                        ),
                                      ),
                                      if (widget.voiceEnabled &&
                                          (sound ||
                                              (voice?.speaking ?? false) ||
                                              busy))
                                        TextButton(
                                          onPressed: () async {
                                            setState(() => sound = false);
                                            await voice?.stop();
                                          },
                                          child: const Text('Без звука'),
                                        ),
                                    ],
                                  ),
                                  if (!widget.voiceEnabled)
                                    const Text(
                                      'Озвучка выключена в настройках.',
                                      style: TextStyle(color: muted),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (busy)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  'Обрабатываю речь… Можно продолжить кнопками.',
                                ),
                              ),
                            if (notice.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(notice),
                                ),
                              ),
                            if (!atChoice && chosen == null)
                              FilledButton(
                                onPressed: advance,
                                child: const Text('Дальше'),
                              ),
                            if (atChoice) ...[
                              for (var i = 0; i < scene.choices.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: OutlinedButton(
                                    onPressed: () => choose(i),
                                    child: Text(
                                      '${i + 1}. ${scene.choices[i].label}',
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              FilledButton.icon(
                                onPressed: busy ? null : listen,
                                icon: CozyIcon(
                                  listening
                                      ? Icons.stop_circle_outlined
                                      : Icons.mic_none_rounded,
                                ),
                                label: Text(
                                  listening
                                      ? 'Готово, распознать'
                                      : 'Ответить голосом',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                listening
                                    ? 'Слушаю · до 12 секунд. Нажми «Готово», когда закончишь.'
                                    : 'Скажи «первый вариант», «второй вариант» или «помоги».',
                                style: const TextStyle(color: muted),
                              ),
                              if (transcript.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text('Я услышал: «$transcript»'),
                                  ),
                                ),
                              if (pending != null)
                                FilledButton(
                                  onPressed: () => choose(pending!),
                                  child: Text(
                                    'Подтвердить: ${scene.choices[pending!].label}',
                                  ),
                                ),
                            ],
                            if (chosen != null) ...[
                              FilledButton(
                                onPressed: () async {
                                  await voice?.stop();
                                  if (mounted) widget.onContinue();
                                },
                                child: const Text('К заданию главы'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await voice?.stop();
                                  if (mounted) {
                                    setState(() {
                                      chosen = pending = null;
                                      transcript = '';
                                    });
                                    showReaction('look');
                                    showReplyStart();
                                  }
                                },
                                child: const Text('Обсудить другой вариант'),
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Text(
                              'Голос работает на устройстве. Микрофон включается только по кнопке. '
                              'Запись удаляется после распознавания. Все действия доступны без голоса.',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
