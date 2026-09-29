import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/content.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('Catalog IDs, prices and categories match the single game canon', () {
    final canon =
        jsonDecode(File('../content/game-canon.json').readAsStringSync())
            as Map<String, dynamic>;
    final store = (canon['store'] as List).cast<Map<String, dynamic>>();
    expect(
      catalogItems.map((item) => item.id).toSet(),
      store.map((item) => item['id']).toSet(),
    );
    for (final item in catalogItems) {
      final expected = store.singleWhere((row) => row['id'] == item.id);
      expect(item.price, expected['price'], reason: item.id);
      expect(
        item.required,
        expected['category'] == 'required',
        reason: item.id,
      );
    }
  });

  test(
    'Legacy care IDs migrate without losing balances, purchases or paid care',
    () {
      final old = (GameState()..cared.addAll([0, 2])).toJson()
        ..['purchased'] = ['food', 'shampoo', 'leash', 'vitamins', 'bow']
        ..['wallet'] = [21, 62, 9]
        ..['equippedWearable'] = 'bow';
      final migrated = GameState.fromJson(old);
      expect(migrated.wallet, [21, 62, 9]);
      expect(migrated.purchased, {
        'food_refill',
        'clean_care',
        'leash',
        'vitamins',
        'bow',
      });
      expect(migrated.equippedWearable, 'bow');
      expect(migrated.careCost(0), 0);
      expect(migrated.careCost(2), 0);
      expect(migrated.takePendingFinanceMutations(), isEmpty);
    },
  );

  test(
    'Care stays paid after reload, duplicate delivery and changing entry point',
    () async {
      sqfliteFfiInit();
      final store = await GameStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.close);
      final food = catalogItems.singleWhere((item) => item.id == 'food_refill');
      final clean = catalogItems.singleWhere((item) => item.id == 'clean_care');
      await store.change('food1', 'Корм', (state) => state.buyItem(food));
      await store.change('food1', 'Корм', (state) => state.buyItem(food));
      await store.change('room1', 'Повтор в комнате', (state) => state.care(0));
      await store.change('clean1', 'Чистота', (state) => state.care(2));
      await store.change(
        'shopclean',
        'Повтор в каталоге',
        (state) => state.buyItem(clean),
      );
      var state = await store.load();
      expect(state.wallet, [85, 0, 0]);
      expect(state.needs, [85, 65, 80]);
      final events = await store.db.query('operation_events');
      expect(
        events.where((e) => e['amount'] == 10 || e['amount'] == 5),
        hasLength(2),
      );
      await store.change('next', 'Следующий день', (state) => state.endDay());
      state = await store.change(
        'food2',
        'Корм следующего дня',
        (state) => state.buyItem(food),
      );
      expect(state.wallet, [75, 0, 0]);
      expect(state.careCost(0), 0);
      expect(state.careCost(2), 5);
    },
  );
}
