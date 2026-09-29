import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper_tokenizer.dart';

void main() {
  test('all exported classifier questions have exact WordPiece ids', () {
    final export = '${Directory.current.path}/assets/helper';
    final vocab = File('$export/vocab.txt').readAsLinesSync();
    final cases = (jsonDecode(File('test/fixtures/finance_helper_parity.json').readAsStringSync())
        as List<dynamic>);
    final tokenizer = FinanceHelperTokenizer(vocab);
    expect(cases, hasLength(29));
    for (final item in cases.cast<Map<String, dynamic>>()) {
      expect(
        tokenizer.encode(item['q'] as String),
        item['ids'],
        reason: item['q'] as String,
      );
    }
  });
}
