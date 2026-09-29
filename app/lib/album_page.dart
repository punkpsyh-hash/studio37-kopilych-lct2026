import 'package:flutter/material.dart';
import 'cartoon_props.dart';
import 'content.dart';
import 'game.dart';
import 'ui.dart';

class AlbumEntry {
  const AlbumEntry(this.id, this.title, this.lines, this.prop);
  final String id, title;
  final List<String> lines;
  final CartoonProp prop;
}

/// A read-only projection of saved facts. No inferred dates or new rewards.
List<AlbumEntry> albumEntries(GameState state) {
  final durablePurchases = catalogItems
      .where((item) => !item.required && state.purchased.contains(item.id))
      .toList(growable: false);
  return [
    if (state.name != null)
      AlbumEntry('friend', 'Наш новый друг', [
        '${state.name} теперь живёт с тобой.',
        'Твой питомец — ${speciesNames[state.species].toLowerCase()}.',
      ], CartoonProp.heart),
    for (final fact in state.facts.where((fact) => !fact.synthetic))
      AlbumEntry(
        'day:${fact.day}',
        'День ${fact.day}',
        [
          'Вы составили план и завершили этот день.',
          if (fact.caredAll) 'Питомец получил все три заботы.',
          if (fact.factKnown) ...[
            'На заботу и необходимое: ${fact.mandatorySpent} монет.',
            'На желания: ${fact.wantsSpent} монет.',
            'Изменение накоплений: ${fact.netSavings! > 0 ? "+" : ""}${fact.netSavings} монет.',
          ] else
            'Подробные суммы этого дня не сохранились.',
        ],
        fact.caredAll ? CartoonProp.heart : CartoonProp.clipboard,
      ),
    for (final goal in goals.where((goal) => state.owned.contains(goal.id)))
      AlbumEntry(
        'dream:${goal.id}',
        'Мечта сбылась',
        ['Вы накопили на «${goal.name}». Теперь эта вещь есть дома.'],
        switch (goal.id) {
          'garden' => CartoonProp.garden,
          'stars' => CartoonProp.lamp,
          _ => CartoonProp.house,
        },
      ),
    if (durablePurchases.isNotEmpty)
      AlbumEntry('purchases', 'Выбрали для дома', [
        for (final item in durablePurchases) item.name,
      ], CartoonProp.house),
    if (allMissions.any((mission) => state.completed.contains(mission.id)))
      AlbumEntry('lessons', 'Уже умеем', [
        for (final mission in allMissions.where(
          (mission) => state.completed.contains(mission.id),
        ))
          mission.title,
      ], CartoonProp.clipboard),
    if (householdJobs.values.any(
      (job) => state.completed.contains('job:${job.id}'),
    ))
      AlbumEntry('jobs', 'Помогали дома', [
        for (final job in householdJobs.values.where(
          (job) => state.completed.contains('job:${job.id}'),
        ))
          job.title,
      ], CartoonProp.sofa),
    if (state.achievedStage > 1)
      AlbumEntry('growth', 'Растём вместе', [
        state.stageName,
      ], CartoonProp.garden),
  ];
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.state});
  final GameState state;
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final controller = PageController();
  late final pages = albumEntries(widget.state);
  int page = 0;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void turn(int next) {
    if (next < 0 || next >= pages.length) return;
    if (widget.state.reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(next);
    } else {
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: Navigator.canPop(context) ? const CozyBackButton() : null,
      title: Text(widget.state.demoMode ? 'Пример альбома' : 'Наш альбом'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (pages.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Пока здесь чистые страницы. В них появятся ваши поступки и открытия.',
                  ),
                ),
              ),
            )
          else ...[
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, index) {
                  final memory = pages[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Surface(
                      color: const Color(0xFFFFFAEB),
                      padding: const EdgeInsets.all(20),
                      child: ListView(
                        key: PageStorageKey('album:${memory.id}'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PropArt(memory.prop, size: 76),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            memory.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 18),
                          for (final line in memory.lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          if (widget.state.purchased.contains('stickers')) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              label: 'Твои наклейки украшают страницу',
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Предыдущая страница',
                    onPressed: page > 0 ? () => turn(page - 1) : null,
                    icon: const CozyIcon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      label: 'Страница ${page + 1} из ${pages.length}',
                      child: ExcludeSemantics(
                        child: Text(
                          '${page + 1} / ${pages.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Следующая страница',
                    onPressed: page + 1 < pages.length
                        ? () => turn(page + 1)
                        : null,
                    icon: const CozyIcon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
