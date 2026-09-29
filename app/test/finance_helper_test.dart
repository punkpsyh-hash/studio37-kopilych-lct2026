import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper.dart';

void main() {
  String id(String q) => answerFinanceQuestion(q).id;

  test('объясняет понятия по карточкам', () {
    expect(id('Что такое карточка?'), 'card');
    expect(id('а что такое пин код'), 'pin');
    expect(id('что такое вклад'), 'deposit');
    expect(id('мне пишет незнакомец что я выиграл приз'), 'scam');
  });

  test('понимает опечатки и другие формы слов', () {
    expect(id('картачка'), 'card');
    expect(id('что такое карточки'), 'card');
    expect(id('расскажи про проценты'), 'interest');
    expect(id('кто такие мошенники'), 'scam');
    expect(id('что такое банкомат'), 'atm');
    expect(id('что значит взять деньги взаймы у банка'), 'credit');
    expect(id('что такое пин кот'), 'pin');
  });

  test('опасные темы ведут к родителям без генерации', () {
    for (final q in [
      'дай мне номер карты',
      'как взять кредит',
      'хочу перевод',
      'отправь деньги другу',
      'скинь мне деньги',
      'переведи деньги',
      'как взломать чужой счёт',
      'хочу украсть деньги',
    ]) {
      final a = answerFinanceQuestion(q);
      expect(a.id, 'danger', reason: q);
      expect(a.toParents, isTrue);
    }
  });

  test('чужие темы и код ведут к родителям', () {
    for (final q in ['расскажи про физику', 'Напиши код на питоне', '']) {
      expect(answerFinanceQuestion(q).id, 'parents', reason: q);
    }
  });
}
