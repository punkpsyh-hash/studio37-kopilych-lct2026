import 'package:flutter/material.dart';
import 'cartoon_props.dart';

const ink = Color(0xFF493622),
    muted = Color(0xFF78644D),
    blue = Color(0xFF526D37);
const cream = Color(0xFFFFF7E4),
    sage = Color(0xFFE4ECD2),
    peach = Color(0xFFF8E4CB);
const caramel = Color(0xFFAE8054);

final _cozyIconNames = <IconData, String>{
  Icons.account_balance_wallet_outlined: 'wallet',
  Icons.account_balance_wallet_rounded: 'wallet',
  Icons.arrow_back_rounded: 'back',
  Icons.arrow_forward_rounded: 'forward',
  Icons.auto_awesome_rounded: 'sparkle',
  Icons.auto_stories_outlined: 'story-book',
  Icons.auto_stories_rounded: 'story-book',
  Icons.bathtub_rounded: 'bathroom',
  Icons.bed_rounded: 'catalog-bed',
  Icons.celebration_outlined: 'celebration',
  Icons.check_circle_outline: 'check',
  Icons.check_circle_rounded: 'check',
  Icons.check_rounded: 'check',
  Icons.checkroom_rounded: 'clothing',
  Icons.chevron_left_rounded: 'back',
  Icons.chevron_right_rounded: 'forward',
  Icons.close_rounded: 'close',
  Icons.cottage_outlined: 'home',
  Icons.cottage_rounded: 'home',
  Icons.cruelty_free_rounded: 'hamster-face',
  Icons.delete_forever_rounded: 'trash',
  Icons.edit_calendar_rounded: 'calendar',
  Icons.explore_rounded: 'map-route',
  Icons.fact_check_outlined: 'job-checklist',
  Icons.family_restroom_rounded: 'adult-family',
  Icons.favorite_border_rounded: 'heart',
  Icons.favorite_rounded: 'heart',
  Icons.flag_outlined: 'goal',
  Icons.flag_rounded: 'goal',
  Icons.history_rounded: 'history',
  Icons.lightbulb_outline_rounded: 'hint-lamp',
  Icons.lightbulb_rounded: 'hint-lamp',
  Icons.lock_outline_rounded: 'lock',
  Icons.menu_book_rounded: 'story-book',
  Icons.mic_none_rounded: 'microphone',
  Icons.nightlight_round_rounded: 'night-light',
  Icons.nights_stay_rounded: 'sleep',
  Icons.pets_outlined: 'pet-paw',
  Icons.pets_rounded: 'pet-paw',
  Icons.photo_album_outlined: 'album',
  Icons.privacy_tip_outlined: 'shield',
  Icons.radio_button_checked: 'radio-selected',
  // radio_button_off is the same IconData as radio_button_unchecked.
  Icons.radio_button_unchecked: 'radio-empty',
  Icons.record_voice_over_rounded: 'speaker',
  Icons.refresh_rounded: 'refresh',
  Icons.restart_alt_rounded: 'refresh',
  Icons.restaurant_rounded: 'food',
  Icons.route_outlined: 'map-route',
  Icons.route_rounded: 'map-route',
  Icons.savings_outlined: 'savings',
  Icons.science_outlined: 'science',
  Icons.shield_outlined: 'shield',
  Icons.shopping_bag_outlined: 'shop-bag',
  Icons.shopping_basket_outlined: 'shop-bag',
  Icons.smart_display_outlined: 'video-demo',
  Icons.soap_rounded: 'soap',
  Icons.sports_baseball_outlined: 'play-ball',
  Icons.sports_baseball_rounded: 'play-ball',
  Icons.stop_circle_outlined: 'stop',
  Icons.stop_rounded: 'stop',
  Icons.storefront_rounded: 'shop-bag',
  Icons.swap_horiz_rounded: 'transfer',
  Icons.task_alt_rounded: 'check',
  Icons.tune_rounded: 'settings',
  Icons.verified_rounded: 'check',
  Icons.view_in_ar_rounded: 'view-3d',
  Icons.visibility_rounded: 'eye',
  Icons.volume_up_rounded: 'speaker',
  Icons.yard_rounded: 'garden',
};

class CozyImage extends StatelessWidget {
  const CozyImage(this.name, {super.key, this.size = 24, this.semanticLabel});
  final String name;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/art/ui-cozy/$name.webp',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
      64,
      256,
    ),
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
  );
}

class CozyIcon extends StatelessWidget {
  const CozyIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => CozyImage(
    _cozyIconNames[icon]!,
    size: size ?? IconTheme.of(context).size ?? 24,
    semanticLabel: semanticLabel,
  );
}

class CozyBackButton extends StatelessWidget {
  const CozyBackButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Назад',
    onPressed: onPressed ?? () => Navigator.maybePop(context),
    icon: const CozyIcon(Icons.arrow_back_rounded),
  );
}

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Nunito',
  scaffoldBackgroundColor: cream,
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    surface: cream,
    primary: blue,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.18,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 17, height: 1.4, color: ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: ink),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 54),
      backgroundColor: blue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFB7B5A5),
      elevation: 4,
      shadowColor: const Color(0x66514225),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: const BorderSide(color: Color(0xFF3F582A)),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 50),
      foregroundColor: ink,
      backgroundColor: const Color(0xFFFFFBF0),
      side: const BorderSide(color: caramel, width: 1.4),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: blue,
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFFFFBF1),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD7BD98)),
    ),
    contentPadding: const EdgeInsets.all(18),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  chipTheme: const ChipThemeData(showCheckmark: false),
  appBarTheme: const AppBarTheme(
    backgroundColor: cream,
    foregroundColor: ink,
    scrolledUnderElevation: 0,
  ),
);

class Heading extends StatelessWidget {
  const Heading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      if (subtitle != null) ...[
        const SizedBox(height: 10),
        Text(
          subtitle!,
          style: const TextStyle(color: muted, fontSize: 17, height: 1.4),
        ),
      ],
    ],
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color = cream,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(color, Colors.white, .35)!, color],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD8BA91), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x20523C24),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class Coins extends StatelessWidget {
  const Coins(this.amount, {super.key});
  final int amount;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$amount монет',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PropArt(CartoonProp.coin, size: 28),
          const SizedBox(width: 5),
          Text(
            '$amount',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    children: [
      if (icon != null) CozyIcon(icon, color: blue, size: 18),
      Text(
        text,
        style: const TextStyle(
          color: blue,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    ],
  );
}

class NeedMeter extends StatelessWidget {
  const NeedMeter({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value из 100',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label $value',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value / 100,
              color: color,
              backgroundColor: const Color(0xFFE9E4DA),
              minHeight: 7,
            ),
          ),
        ],
      ),
    ),
  );
}

class CareButton extends StatelessWidget {
  const CareButton({
    super.key,
    required this.index,
    required this.busy,
    required this.onTap,
  });
  final int index;
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: [peach, sage, const Color(0xFFE8E9DA)][index],
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: caramel, width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26523C24),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
          child: Column(
            children: [
              PropArt(
                [CartoonProp.bowl, CartoonProp.ball, CartoonProp.soap][index],
                size: 40,
              ),
              const SizedBox(height: 7),
              Text(
                ['Кормить', 'Играть', 'Купать'][index],
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${index == 0 ? 10 : 5} монет',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: child,
      ),
    ),
  );
}
