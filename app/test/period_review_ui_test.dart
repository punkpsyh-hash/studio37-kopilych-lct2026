import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/game.dart';
import 'package:kopilych/period_review.dart';
import 'package:kopilych/ui.dart';

DayFact period({List<int> plan = const [15, 0, 10]}) => DayFact(
  1,
  plan,
  const [75, 10, 0],
  true,
  mandatorySpent: 15,
  wantsSpent: 0,
  savingsDeposits: 10,
  savingsWithdrawals: 0,
  goalSpent: 0,
  income: 0,
);

Widget reviewApp(
  DayFact fact,
  ValueChanged<PeriodReviewDecision?> onDone, {
  double textScale = 1,
}) => MaterialApp(
  theme: appTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => onDone(
          await showModalBottomSheet<PeriodReviewDecision>(
            context: context,
            isScrollControlled: true,
            builder: (_) =>
                PeriodReviewSheet(summary: fact, qualifyingPeriods: 2),
          ),
        ),
        child: const Text('Открыть итоги'),
      ),
    ),
  ),
);

void main() {
  testWidgets('matching plan closes after review without a made-up reason', (
    tester,
  ) async {
    PeriodReviewDecision? decision;
    await tester.pumpWidget(reviewApp(period(), (value) => decision = value));
    await tester.tap(find.text('Открыть итоги'));
    await tester.pumpAndSettle();
    expect(find.text('План и факт совпали.'), findsOneWidget);
    expect(find.textContaining('Что изменилось?'), findsNothing);
    expect(find.textContaining('3-м зачтённым'), findsOneWidget);
    final finish = find.byKey(const ValueKey('finish-reviewed-period'));
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(decision, isNotNull);
    expect(decision!.explanation, isNull);
  });

  testWidgets('deviation needs an explicit reason and scrolls at 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PeriodReviewDecision? decision;
    await tester.pumpWidget(
      reviewApp(
        period(plan: [15, 10, 0]),
        (value) => decision = value,
        textScale: 2,
      ),
    );
    await tester.tap(find.text('Открыть итоги'));
    await tester.pumpAndSettle();
    final finish = find.byKey(const ValueKey('finish-reviewed-period'));
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);
    final reason = find.text('Я решил отложить покупку');
    await tester.ensureVisible(reason);
    await tester.tap(reason);
    await tester.pumpAndSettle();
    await tester.ensureVisible(finish);
    expect(tester.getSize(finish).height, greaterThanOrEqualTo(48));
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(decision?.explanation, 'Я решил отложить покупку');
    expect(tester.takeException(), isNull);
  });

  testWidgets('return to current day cancels without a review decision', (
    tester,
  ) async {
    var returned = false;
    PeriodReviewDecision? decision;
    await tester.pumpWidget(
      reviewApp(period(), (value) {
        returned = true;
        decision = value;
      }),
    );
    await tester.tap(find.text('Открыть итоги'));
    await tester.pumpAndSettle();
    final back = find.text('Продолжить этот день');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(decision, isNull);
  });

  testWidgets(
    'old unknown facts are not presented as a matched plan or growth',
    (tester) async {
      await tester.pumpWidget(
        reviewApp(const DayFact(1, [20, 0, 10], [70, 0, 0], true), (_) {}),
      );
      await tester.tap(find.text('Открыть итоги'));
      await tester.pumpAndSettle();
      expect(find.textContaining('В старом сохранении'), findsOneWidget);
      expect(find.text('План и факт совпали.'), findsNothing);
      expect(find.textContaining('3-м зачтённым'), findsNothing);
    },
  );
}
