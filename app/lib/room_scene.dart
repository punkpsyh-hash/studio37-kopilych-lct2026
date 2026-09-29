import 'package:flutter/material.dart';
import 'ui.dart';

enum HomeRoom {
  living('Гостиная', 'living', 'Играть', 0, Icons.sports_baseball_rounded, 1),
  kitchen('Кухня', 'kitchen', 'Кормить', 10, Icons.restaurant_rounded, 0),
  bathroom('Ванная', 'bathroom', 'Купать', 5, Icons.bathtub_rounded, 2);

  const HomeRoom(
    this.label,
    this.assetName,
    this.actionLabel,
    this.price,
    this.icon,
    this.careIndex,
  );

  final String label, assetName, actionLabel;
  final int price, careIndex;
  final IconData icon;
  String get asset => 'assets/art/room-$assetName.png';
}

/// A room image and one explicit, accessible care interaction.
/// The pet is passed separately so the child's chosen species persists across rooms.
class RoomStage extends StatelessWidget {
  const RoomStage({
    super.key,
    required this.room,
    required this.pet,
    required this.onCare,
    required this.busy,
    required this.reducedMotion,
    this.onInspect,
  });

  final HomeRoom room;
  final Widget pet;
  final VoidCallback onCare;
  final bool busy, reducedMotion;
  final VoidCallback? onInspect;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 360 / 310,
    child: Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          child: Image.asset(
            room.asset,
            key: ValueKey(room),
            fit: BoxFit.fill,
            semanticLabel: '${room.label}: игровая комната',
          ),
        ),
        pet,
        if (onInspect != null)
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: 'Осмотреть 3D-предмет комнаты',
              onPressed: onInspect,
              icon: const CozyIcon(Icons.view_in_ar_rounded),
            ),
          ),
        Positioned(
          left: room == HomeRoom.bathroom ? null : 12,
          right: room == HomeRoom.bathroom ? 12 : null,
          bottom: 12,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : onCare,
            icon: CozyIcon(room.icon, size: 19),
            label: Text('${room.actionLabel} · ${room.price}'),
          ),
        ),
      ],
    ),
  );
}
