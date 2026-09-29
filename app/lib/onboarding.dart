import 'package:flutter/material.dart';
import 'art.dart';
import 'game.dart';
import 'meshy_pet_view.dart';
import 'ui.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({
    super.key,
    required this.busy,
    required this.onStart,
    this.useMeshyModels = false,
  });
  final bool busy;
  final bool useMeshyModels;
  final Future<bool> Function(int, int, int, String) onStart;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int species = 0, color = 0, accessory = 0;
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Row(
                children: [
                  CozyIcon(Icons.pets_rounded, color: blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'копилыч',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/art/cover-hamster-meshy.png',
                  semanticLabel:
                      'Три друга — котёнок, щенок и хомячок — у копилки с монетками',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Большие мечты\nначинаются с дружбы',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'В Доме маленьких мечт тебя ждёт новый друг. Выбери питомца: вместе вы обустроите дом, научитесь заботиться, копить и планировать.',
                style: TextStyle(fontSize: 17, color: muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: Semantics(
                  label: 'Превью: ${speciesNames[species]}',
                  child: widget.useMeshyModels
                      ? IgnorePointer(
                          child: MeshyPetView(
                            species: species,
                            interactive: false,
                          ),
                        )
                      : PetScene(
                          species: species,
                          color: color,
                          accessory: accessory,
                          room: false,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    ChoiceChip(
                      label: Text(speciesNames[i]),
                      selected: species == i,
                      onSelected: (_) => setState(() => species = i),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Твой неповторимый',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.useMeshyModels
                    ? 'Выбери цвет для иллюстраций'
                    : 'Выбери окрас',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < petColors.length; i++)
                    Semantics(
                      label: 'Окрас ${i + 1}',
                      selected: color == i,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => color = i),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: petColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == i ? ink : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: color == i
                              ? const CozyIcon(Icons.check_rounded, color: ink)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.useMeshyModels)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'В игровом доме питомец выглядит как на 3D-превью. Цвет и аксессуар появятся в его иллюстрациях.',
                    style: TextStyle(color: muted),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    ChoiceChip(
                      label: Text(['Без аксессуара', 'Шарфик', 'Бабочка'][i]),
                      selected: accessory == i,
                      onSelected: (_) => setState(() => accessory = i),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: name,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Как назовём друга?',
                  hintText: defaultNames[species],
                  helperText: 'Оставь пустым — будет ${defaultNames[species]}',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: widget.busy
                    ? null
                    : () =>
                          widget.onStart(species, color, accessory, name.text),
                child: Text(widget.busy ? 'Знакомимся…' : 'Это мой друг'),
              ),
              const SizedBox(height: 12),
              const Text(
                '100 игровых монет на первые маленькие планы.\nВсе питомцы доступны бесплатно.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
