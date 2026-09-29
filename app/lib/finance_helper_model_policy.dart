import 'dart:math';

import 'finance_helper.dart';

class FinanceChoice {
  const FinanceChoice(this.id, this.title, this.text);
  final String id;
  final String title;
  final String text;
}

class FinanceModelAnswer {
  const FinanceModelAnswer(this.text, {this.choices = const []});
  final String text;
  final List<FinanceChoice> choices;
  bool get needsChoice => choices.isNotEmpty;
}

/// Applies safety rules and verified card content to classifier probabilities.
/// Nothing in this class can change the wallet or write a save.
class FinanceHelperModelPolicy {
  FinanceHelperModelPolicy({
    required this.labels,
    required this.cards,
    required this.chat,
    required this.parentsText,
    this.answerThreshold = .75,
    this.askThreshold = .35,
    Random? random,
  }) : _random = random ?? Random();

  final List<String> labels;
  final Map<String, FinanceChoice> cards;
  final Map<String, List<String>> chat;
  final String parentsText;
  final double answerThreshold;
  final double askThreshold;
  final Random _random;

  FinanceModelAnswer? safetyAnswer(String question) {
    final rule = answerFinanceQuestion(question);
    return rule.id == 'danger' ? FinanceModelAnswer(rule.text) : null;
  }

  FinanceModelAnswer fallback(String question) =>
      FinanceModelAnswer(answerFinanceQuestion(question).text);

  FinanceModelAnswer answer(String question, List<double> probabilities) {
    final safety = safetyAnswer(question);
    if (safety != null) return safety;
    if (probabilities.length != labels.length ||
        probabilities.any((p) => !p.isFinite || p < 0 || p > 1)) {
      return FinanceModelAnswer(parentsText);
    }
    final order = List<int>.generate(labels.length, (i) => i)
      ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));
    if (order.isEmpty) return FinanceModelAnswer(parentsText);
    final top = labels[order.first];
    final p1 = probabilities[order.first];
    if (p1 >= answerThreshold) {
      if (top == 'parents' || top == 'danger') {
        return FinanceModelAnswer(parentsText);
      }
      if (top == 'calc') return FinanceModelAnswer(_calculate(question));
      final replies = chat[top];
      if (replies != null && replies.isNotEmpty) {
        return FinanceModelAnswer(replies[_random.nextInt(replies.length)]);
      }
      return FinanceModelAnswer(cards[top]?.text ?? parentsText);
    }
    if (p1 >= askThreshold) {
      final choices = <FinanceChoice>[
        for (final index in order)
          if (cards.containsKey(labels[index])) cards[labels[index]]!,
      ].take(2).toList();
      if (choices.isNotEmpty) {
        return FinanceModelAnswer(
          'Ты спрашиваешь про:',
          choices: choices,
        );
      }
    }
    return FinanceModelAnswer(parentsText);
  }

  String _calculate(String question) {
    final values = RegExp(r'\d+')
        .allMatches(question)
        .map((match) => int.tryParse(match.group(0)!))
        .toList();
    if (values.length != 2 || values.any((value) => value == null)) {
      return parentsText;
    }
    final a = values[0]!, b = values[1]!;
    final q = question.toLowerCase().replaceAll('ё', 'е');
    if (RegExp(r'за сколько').hasMatch(q) &&
        RegExp(r'накопить|нужно').hasMatch(q) &&
        RegExp(r'(^|[^а-я])по([^а-я]|$)').hasMatch(q)) {
      if (b <= 0 || a % b != 0) return parentsText;
      final period = RegExp(r'недел').hasMatch(q)
          ? 'недель'
          : RegExp(r'месяц').hasMatch(q)
              ? 'месяцев'
              : 'дней';
      return 'Считаем: $a разделить на $b. Получится ${a ~/ b} $period.';
    }
    if (RegExp(r'(^|[^а-я])по[^\n]*за[^\n]*(дн|недел|месяц)|в день|в неделю')
        .hasMatch(q)) {
      return 'Считаем: $a умножить на $b. Получится ${a * b} монет.';
    }
    if (RegExp(r'еще|добавили|плюс|дали|всего').hasMatch(q)) {
      return 'Считаем: $a плюс $b. Получится ${a + b} монет.';
    }
    if (RegExp(r'потратил|осталось|минус|отдал').hasMatch(q)) {
      final high = max(a, b), low = min(a, b);
      return 'Считаем: $high минус $low. Получится ${high - low} монет.';
    }
    return parentsText;
  }
}
