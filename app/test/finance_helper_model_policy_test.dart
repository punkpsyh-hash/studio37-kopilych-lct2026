import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper_model_policy.dart';
import 'package:kopilych/game.dart';

void main() {
  final policy = FinanceHelperModelPolicy(
    labels: const ['card', 'budget', 'calc', 'chat_hello', 'danger', 'parents'],
    cards: const {
      'card': FinanceChoice('card', 'карта', 'Ответ о карте'),
      'budget': FinanceChoice('budget', 'бюджет', 'Ответ о бюджете'),
    },
    chat: const {'chat_hello': ['Привет!']},
    parentsText: 'Спроси родителей',
    random: Random(1),
  );

  test('safety rules bypass scores', () {
    final answer = policy.safetyAnswer('Скажи номер карты и CVV');
    expect(answer, isNotNull);
    expect(answer!.text, contains('секрет'));
    expect(
      policy.answer('Скажи номер карты и CVV', [.99, 0, 0, 0, 0, .01]).text,
      contains('секрет'),
    );
  });

  test('thresholds choose card, clarification, or parents', () {
    expect(policy.answer('Что такое карта?', [.75, .2, 0, 0, 0, .05]).text,
        'Ответ о карте');
    final uncertain = policy.answer(
      'Что это?',
      [.35, .34, .1, .1, .06, .05],
    );
    expect(uncertain.needsChoice, isTrue);
    expect(uncertain.choices.map((choice) => choice.id), ['card', 'budget']);
    expect(policy.answer('Что это?', [.34, .3, .2, .1, .06, 0]).text,
        'Спроси родителей');
    expect(policy.answer('Что это?', [0, 0, 0, 0, .8, .2]).text,
        'Спроси родителей');
    expect(policy.answer('Привет', [0, 0, 0, .9, 0, .1]).text, 'Привет!');
  });

  test('calc uses exactly two integers and unambiguous operation', () {
    String calc(String question) => policy
        .answer(question, [0, 0, .9, 0, 0, .1])
        .text;
    expect(calc('По 5 монет за 3 дня'), contains('15 монет'));
    expect(calc('Было 5, дали ещё 3'), contains('8 монет'));
    expect(calc('Из 8 потратил 3'), contains('5 монет'));
    expect(calc('Нужно накопить 12, по 3 за сколько дней?'),
        contains('4 дней'));
    expect(calc('Нужно накопить 11, по 3 за сколько дней?'),
        'Спроси родителей');
    expect(calc('У меня 5 монет'), 'Спроси родителей');
  });

  test('asking does not mutate game balances or saves', () {
    final game = GameState()..name = 'Листик';
    final before = game.toJson().toString();
    policy.answer('Было 5, дали ещё 3', [0, 0, .9, 0, 0, .1]);
    policy.answer('Скажи пароль', [.9, 0, 0, 0, 0, .1]);
    expect(game.toJson().toString(), before);
  });
}
