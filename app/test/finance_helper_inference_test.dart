import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/finance_helper_model.dart';

void main() {
  test(
    'int8 classifier reproduces exported intent parity',
    () async {
      final root = '${Directory.current.path}/assets/helper';
      final labels = (jsonDecode(File('$root/labels.json').readAsStringSync())
              as List<dynamic>)
          .cast<String>();
      final cases = (jsonDecode(File('test/fixtures/finance_helper_parity.json').readAsStringSync())
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var matched = 0;
      for (final item in cases) {
        final result = await inferFinanceIntent(
          '$root/model_int8.onnx',
          (item['ids'] as List<dynamic>).cast<int>(),
        );
        expect(result, hasLength(labels.length));
        final top = result.indexOf(result.reduce((a, b) => a > b ? a : b));
        if (labels[top] == item['top']) matched++;
        if (labels[top] == item['top']) {
          expect(result[top], closeTo((item['p'] as num).toDouble(), .05));
        }
      }
      expect(matched, greaterThanOrEqualTo(27));
    },
    skip: Platform.environment['KOPILYCH_TEST_NATIVE_ONNX'] != '1'
        ? 'Enable with a compatible local ONNX Runtime DLL'
        : false,
  );
}
