import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'finance_helper_model_policy.dart';
import 'finance_helper_tokenizer.dart';

/// An ONNX session is confined to a bounded worker isolate and always freed.
Future<List<double>> inferFinanceIntent(String modelPath, List<int> ids) =>
    Isolate.run(() {
      OrtEnv.instance.init();
      final options = OrtSessionOptions()..setIntraOpNumThreads(2);
      OrtSession? session;
      OrtValueTensor? idTensor, maskTensor;
      OrtRunOptions? runOptions;
      List<OrtValue?>? outputs;
      try {
        session = OrtSession.fromBuffer(
          File(modelPath).readAsBytesSync(),
          options,
        );
        idTensor = OrtValueTensor.createTensorWithDataList(ids, [1, ids.length]);
        maskTensor = OrtValueTensor.createTensorWithDataList(
          List<int>.filled(ids.length, 1),
          [1, ids.length],
        );
        runOptions = OrtRunOptions();
        outputs = session.run(runOptions, {
          'input_ids': idTensor,
          'attention_mask': maskTensor,
        }, ['probs']);
        final rows = outputs.single?.value as List<dynamic>;
        return (rows.single as List<dynamic>)
            .map((value) => (value as num).toDouble())
            .toList();
      } finally {
        for (final output in outputs ?? const <OrtValue?>[]) {
          output?.release();
        }
        runOptions?.release();
        idTensor?.release();
        maskTensor?.release();
        session?.release();
        options.release();
        OrtEnv.instance.release();
      }
    });

/// Holds only verified content and a tokenizer on the UI isolate.
/// Inference errors use the existing rule-based offline helper.
class FinanceHelperModel {
  FinanceHelperModel._(this._modelPath, this._tokenizer, this.policy);

  final String _modelPath;
  final FinanceHelperTokenizer _tokenizer;
  final FinanceHelperModelPolicy policy;

  static Future<FinanceHelperModel> load() async {
    const root = 'assets/helper/';
    final vocab = (await rootBundle.loadString('${root}vocab.txt'))
        .trimRight()
        .split(RegExp(r'\r?\n'));
    final labels = (jsonDecode(await rootBundle.loadString('${root}labels.json'))
            as List<dynamic>)
        .cast<String>();
    final cardsJson = jsonDecode(await rootBundle.loadString('${root}cards.json'))
        as Map<String, dynamic>;
    final rawCards = cardsJson['cards'] as Map<String, dynamic>;
    final chatJson = jsonDecode(await rootBundle.loadString('${root}chat.json'))
        as Map<String, dynamic>;
    final config = jsonDecode(await rootBundle.loadString('${root}config.json'))
        as Map<String, dynamic>;
    final modelFile = File(
      '${(await getApplicationSupportDirectory()).path}/finance-helper-model-int8.onnx',
    );
    if (!await modelFile.exists() || await modelFile.length() != 5626700) {
      final bytes = await rootBundle.load('${root}model_int8.onnx');
      await modelFile.parent.create(recursive: true);
      final temp = File('${modelFile.path}.part');
      await temp.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await temp.rename(modelFile.path);
    }
    return FinanceHelperModel._(
      modelFile.path,
      FinanceHelperTokenizer(vocab, maxLength: config['max_len'] as int),
      FinanceHelperModelPolicy(
        labels: labels,
        cards: {
          for (final entry in rawCards.entries)
            entry.key: FinanceChoice(
              entry.key,
              (entry.value as Map<String, dynamic>)['title'] as String,
              (entry.value as Map<String, dynamic>)['text'] as String,
            ),
        },
        chat: {
          for (final entry in chatJson.entries)
            entry.key: (entry.value as List<dynamic>).cast<String>(),
        },
        parentsText: cardsJson['parents'] as String,
        answerThreshold: (config['answer_threshold'] as num).toDouble(),
        askThreshold: (config['ask_threshold'] as num).toDouble(),
      ),
    );
  }

  Future<FinanceModelAnswer> answer(String question) async {
    final safe = policy.safetyAnswer(question);
    if (safe != null) return safe;
    try {
      final probabilities = await inferFinanceIntent(
        _modelPath,
        _tokenizer.encode(question),
      );
      return policy.answer(question, probabilities);
    } catch (_) {
      return policy.fallback(question);
    }
  }
}
