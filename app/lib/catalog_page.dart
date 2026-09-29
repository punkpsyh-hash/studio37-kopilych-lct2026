import 'package:flutter/material.dart';
import 'content.dart';
import 'controller.dart';
import 'game.dart';
import 'art.dart';
import 'meshy_pet_view.dart';
import 'scene_preview_page.dart';
import 'ui.dart';

typedef ShopRunner =
    Future<bool> Function(
      String label,
      void Function(GameState) action, {
      String? success,
      String? id,
    });

/// Каталог обязательных покупок и желаний питомца.
class CatalogPage extends StatelessWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.onAction,
    this.useMeshyModels = true,
    this.onSceneCare,
    this.onOpenBudget,
  });
  final GameController controller;
  final ShopRunner onAction;
  final bool useMeshyModels;
  final ValueChanged<String>? onSceneCare;
  final VoidCallback? onOpenBudget;

  int _cost(GameState state, CatalogItem item) => item.required
      ? state.careCost(item.id == 'food_refill' ? 0 : 2)
      : item.price;

  String _category(CatalogItem item) =>
      item.required ? 'Обязательная забота' : 'Желание';

  bool _firstBasketReady(GameState state) =>
      state.completed.contains('intro-started') &&
      state.day == 1 &&
      state.cared.containsAll({0, 2}) &&
      !state.purchased.contains('ball');

  Future<void> _confirmFirstBasket(BuildContext context) async {
    final state = controller.state!;
    final ball = catalogItems.singleWhere((item) => item.id == 'ball');
    if (state.wallet[0] < ball.price) {
      await _showInsufficient(context, ball, ball.price);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Заказ для нашего дома'),
        content: Text(
          'В корзине по 1 штуке: корм 10, средство чистоты 5, мяч ${ball.price}. '
          'Корм и чистота уже оплачены, когда ты позаботился о друге. '
          'Сейчас спишем только ${ball.price} монет за мяч. '
          'В «Сейчас» останется ${state.wallet[0] - ball.price}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Проверить ещё раз'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Заказать мяч'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await onAction(
      'Первый заказ: корм, чистота и мяч',
      (game) {
        if (!game.cared.containsAll({0, 2})) {
          throw const GameRule('Сначала позаботимся о питомце.');
        }
        game.buyItem(ball);
      },
      id: 'intro:first-basket:${state.day}',
      success:
          'Мяч теперь в комнате! Уход уже был оплачен, второй раз монеты не списали.',
    );
  }

  String _outcome(GameState state, CatalogItem item, int cost) {
    if (item.required && cost == 0) {
      return 'Забота уже выполнена сегодня; повтор не уменьшит баланс.';
    }
    final effects = <String>[];
    if (item.need >= 0 && item.needBoost > 0) {
      final needName = ['сытость', 'радость', 'чистоту'][item.need];
      final boost = (100 - state.needs[item.need]).clamp(0, item.needBoost);
      effects.add('Повысит $needName на $boost, до 100 максимум');
    }
    if (item.id == 'cap' || item.id == 'bow') {
      effects.add('Аксессуар можно надеть на питомца');
    } else if (item.id == 'stickers') {
      effects.add('Наклейки украсят альбом воспоминаний');
    } else if (item.roomItem) {
      effects.add('Предмет появится в комнате питомца');
    }
    return effects.isEmpty
        ? 'Покупка добавит выбранную вещь питомцу.'
        : '${effects.join('. ')}.';
  }

  Future<void> _showInsufficient(
    BuildContext context,
    CatalogItem item,
    int cost,
  ) async {
    final state = controller.state!;
    final canTransfer = state.wallet[1] > 0 || state.wallet[2] > 0;
    final nextSteps = [
      'Покупку можно отложить — она останется в магазине.',
      if (canTransfer)
        'В бюджете можно перевести монеты из другого конверта в «Сейчас».',
      if (state.incomeAvailable)
        'Можно выполнить оплачиваемое задание этого периода и получить до 30 монет.'
      else
        'Доход этого периода уже получен. После итогов начни новый игровой период — в нём снова будет доступен доход.',
    ];
    final openBudget = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Пока не хватает монет'),
        content: Text(
          '${item.name} стоит $cost монет. Не хватает ${cost - state.wallet[0]} монет в «Сейчас». '
          '\n\n${nextSteps.join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отложить покупку'),
          ),
          if (canTransfer && onOpenBudget != null)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Открыть бюджет'),
            ),
        ],
      ),
    );
    if (openBudget == true && context.mounted) onOpenBudget!();
  }

  Future<void> _confirm(BuildContext context, CatalogItem item) async {
    final s = controller.state!;
    final wearable = item.id == 'cap' || item.id == 'bow';
    final bought = !item.required && s.purchased.contains(item.id);
    final cost = _cost(s, item);
    if (item.required && onSceneCare != null) {
      Navigator.of(context).pop(item.id == 'food_refill' ? 'feed' : 'clean');
      return;
    }
    if (!bought && s.wallet[0] < cost) {
      await _showInsufficient(context, item, cost);
      return;
    }
    final wearing = s.equippedWearable == item.id;
    final bool? yes;
    if (useMeshyModels && (wearable || item.roomItem)) {
      yes = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ScenePreviewPage(
            state: s,
            title: item.name,
            description:
                'Категория: ${_category(item).toLowerCase()}.\n${item.description}\nРезультат: ${_outcome(s, item, cost)}',
            itemId: item.id,
            removeWearable: wearable && bought && wearing,
            priceLabel: bought
                ? wearable
                      ? 'Уже куплено · смена наряда бесплатна'
                      : item.id == 'stickers'
                      ? 'Уже куплено · украшают альбом'
                      : 'Уже куплено · стоит в комнате'
                : s.wallet[0] >= item.price
                ? 'Цена: ${item.price} монет из «Сейчас» · останется ${s.wallet[0] - item.price}'
                : 'Цена: ${item.price} монет · не хватает ${item.price - s.wallet[0]} в «Сейчас»',
            confirmLabel: bought && !wearable
                ? null
                : wearable && bought
                ? wearing
                      ? 'Снять'
                      : 'Надеть'
                : wearable
                ? 'Купить и надеть'
                : 'Купить',
            canConfirm: bought || s.wallet[0] >= item.price,
          ),
        ),
      );
    } else {
      yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag(
                  item.required ? 'ОБЯЗАТЕЛЬНОЕ' : 'ЖЕЛАНИЕ',
                  icon: item.required
                      ? Icons.task_alt_rounded
                      : Icons.favorite_border_rounded,
                ),
                const SizedBox(height: 12),
                Text(item.description),
                const SizedBox(height: 10),
                Text('Результат: ${_outcome(s, item, cost)}'),
                if (wearable) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Примерка на твоём питомце',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(
                    height: 210,
                    width: 280,
                    child: useMeshyModels
                        ? MeshyPetView(species: s.species, wearable: item.id)
                        : PetScene(
                            species: s.species,
                            color: s.color,
                            accessory: item.id == 'cap' ? 3 : 4,
                            room: false,
                            reducedMotion: s.reducedMotion,
                          ),
                  ),
                ],
                if (!bought) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Цена: $cost монет из «Сейчас». Останется ${s.wallet[0] - cost}.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(bought ? 'Закрыть' : 'Передумаю'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                wearable && bought
                    ? wearing
                          ? 'Снять'
                          : 'Надеть'
                    : wearable
                    ? 'Купить и надеть'
                    : 'Купить',
              ),
            ),
          ],
        ),
      );
    }
    if (yes == true && context.mounted) {
      if (wearable && bought) {
        await onAction(
          wearing ? 'Снять: ${item.name}' : 'Надеть: ${item.name}',
          (state) => state.toggleWearable(item.id),
          success: wearing ? 'Аксессуар снят.' : 'Аксессуар надет!',
        );
      } else {
        await onAction(
          'Покупка: ${item.name}',
          (state) => state.buyItem(item),
          success: wearable
              ? 'Покупка готова! Аксессуар уже на питомце.'
              : item.required
              ? 'Готово! ${item.name} порадовало питомца.'
              : 'Отличный выбор! Предмет уже в комнате.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context) ? const CozyBackButton() : null,
        title: const Text('Магазин'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Heading(
                  'Что нужно, а что хочется?',
                  subtitle:
                      'Обязательные вещи заботятся о питомце. Желания делают день ярче — их планируем по остатку.',
                ),
                const SizedBox(height: 20),
                if (_firstBasketReady(controller.state!)) ...[
                  Surface(
                    color: sage,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Первый заказ · 3 вещи',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text('Корм × 1 · уже оплачен'),
                        const Text('Средство чистоты × 1 · уже оплачено'),
                        const Text('Новый мяч × 1 · 15 монет'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('first-day-basket'),
                          onPressed: controller.busy
                              ? null
                              : () => _confirmFirstBasket(context),
                          icon: const CozyIcon(Icons.shopping_basket_rounded),
                          label: const Text('Оформить заказ'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                const Tag('ОБЯЗАТЕЛЬНОЕ', icon: Icons.task_alt_rounded),
                const SizedBox(height: 10),
                for (final item in catalogItems.where((i) => i.required))
                  _itemCard(context, item),
                const SizedBox(height: 18),
                const Tag('ЖЕЛАНИЯ', icon: Icons.favorite_border_rounded),
                const SizedBox(height: 10),
                for (final item in catalogItems.where((i) => !i.required))
                  _itemCard(context, item),
                const SizedBox(height: 14),
                const Text(
                  'В магазине нет настоящих денег: монеты зарабатываются заданиями и хранятся в конверте «Сейчас».',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _itemCard(BuildContext context, CatalogItem item) {
    final s = controller.state!;
    final bought = !item.required && s.purchased.contains(item.id);
    final wearable = item.id == 'cap' || item.id == 'bow';
    final wearing = s.equippedWearable == item.id;
    final cost = _cost(s, item);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final icon = CozyIcon(
      bought
          ? Icons.check_circle_rounded
          : switch (item.id) {
              'food_refill' => Icons.restaurant_rounded,
              'clean_care' => Icons.soap_rounded,
              'ball' => Icons.sports_baseball_rounded,
              'cap' => Icons.checkroom_rounded,
              'nightlight' => Icons.nightlight_round_rounded,
              'cozy_bed' => Icons.bed_rounded,
              _ => Icons.auto_awesome_rounded,
            },
      size: 34,
      color: blue,
    );
    final description = Text(
      item.required && cost == 0
          ? 'Сегодня уже оплачено · повтор бесплатный'
          : wearable
          ? wearing
                ? 'Надето · нажми, чтобы снять или примерить'
                : bought
                ? 'Куплено · нажми, чтобы примерить и надеть'
                : 'Нажми, чтобы бесплатно примерить'
          : bought
          ? item.roomItem && useMeshyModels
                ? 'Уже в комнате · нажми, чтобы посмотреть'
                : 'Уже в комнате'
          : item.description,
      style: const TextStyle(color: muted, fontSize: 14),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_category(item)} · Цена: $cost монет',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        description,
        const SizedBox(height: 4),
        Text(
          'Результат: ${_outcome(s, item, cost)}',
          style: const TextStyle(color: muted, fontSize: 14),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bought
            ? sage
            : item.required
            ? cream
            : peach,
        elevation: 1,
        shadowColor: const Color(0x33514225),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0C9A5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap:
              (bought && !wearable && !(useMeshyModels && item.roomItem)) ||
                  controller.busy
              ? null
              : () => _confirm(context, item),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: largeText
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              item.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            details,
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
