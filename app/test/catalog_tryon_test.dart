import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/catalog_page.dart';
import 'package:kopilych/controller.dart';
import 'package:kopilych/art.dart';
import 'package:kopilych/storage.dart';
import 'package:kopilych/ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('Bow can be previewed for free, bought, removed and worn again', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(
      () => GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    );
    final initial = await tester.runAsync(
      () => store!.change('setup', 'Выбор щенка', (s) {
        s.name = 'Бублик';
        s.species = 1;
        s.reducedMotion = true;
      }),
    );
    final controller = GameController(store!)..state = initial;
    Future<void>? lastAction;
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: CatalogPage(
          controller: controller,
          useMeshyModels: false,
          onAction: (label, action, {success, id}) async {
            lastAction = controller.change(label, action, id: id);
            await lastAction;
            return true;
          },
        ),
      ),
    );

    Future<void> openBow() async {
      await tester.scrollUntilVisible(
        find.text('Праздничный бантик'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Праздничный бантик'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Праздничный бантик'));
      await tester.pumpAndSettle();
    }

    await openBow();
    expect(find.text('Примерка на твоём питомце'), findsOneWidget);
    final preview = tester.widget<PetScene>(find.byType(PetScene));
    expect(preview.species, 1);
    expect(preview.accessory, 4);
    expect(controller.state!.wallet[0], 100);
    await tester.tap(find.text('Передумаю'));
    await tester.pumpAndSettle();
    expect(controller.state!.purchased.contains('bow'), isFalse);

    await openBow();
    await tester.tap(find.text('Купить и надеть'));
    await tester.pump();
    await tester.runAsync(() => lastAction!);
    await tester.pumpAndSettle();
    expect(controller.state!.wallet[0], 82);
    expect(controller.state!.equippedWearable, 'bow');

    await openBow();
    await tester.tap(find.text('Снять'));
    await tester.pump();
    await tester.runAsync(() => lastAction!);
    await tester.pumpAndSettle();
    expect(controller.state!.equippedWearable, isNull);
    expect(controller.state!.wallet[0], 82);

    await openBow();
    await tester.tap(find.text('Надеть'));
    await tester.pump();
    await tester.runAsync(() => lastAction!);
    await tester.pumpAndSettle();
    expect(controller.state!.equippedWearable, 'bow');
    expect(controller.state!.wallet[0], 82);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(store.close);
  });
}
