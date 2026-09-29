import 'dart:math';

import 'package:flutter/material.dart';

import 'finance_helper.dart';
import 'finance_helper_model.dart';
import 'finance_helper_model_policy.dart';

/// Compact floating help UI. Place in a Stack above the full-screen room.
class FinanceHelperPanel extends StatefulWidget {
  const FinanceHelperPanel({
    super.key,
    this.loadModel = FinanceHelperModel.load,
    this.maxCardWidth = 350,
    this.maxCardHeight = 430,
  });

  final Future<FinanceHelperModel> Function() loadModel;
  final double maxCardWidth;
  final double maxCardHeight;

  @override
  State<FinanceHelperPanel> createState() => _FinanceHelperPanelState();
}

class _FinanceHelperPanelState extends State<FinanceHelperPanel> {
  final _input = TextEditingController();
  FinanceHelperModel? _model;
  FinanceModelAnswer? _answer;
  bool _open = false;
  bool _busy = false;
  int _epoch = 0;

  @override
  void dispose() {
    _epoch++;
    _input.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      if (!_open) {
        _epoch++;
        _input.clear();
        _answer = null;
        _busy = false;
      }
    });
    if (_open && _model == null) {
      // Loading is lazy; the rule-based helper remains available on failure.
      widget.loadModel().then((model) {
        if (mounted) setState(() => _model = model);
      }).catchError((Object _) {});
    }
  }

  Future<void> _ask() async {
    final question = _input.text.trim();
    if (question.isEmpty || _busy) return;
    final epoch = ++_epoch;
    setState(() => _busy = true);
    try {
      final answer = _model == null
          ? FinanceModelAnswer(answerFinanceQuestion(question).text)
          : await _model!.answer(question);
      if (mounted && epoch == _epoch) setState(() => _answer = answer);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_open) {
      return Semantics(
        button: true,
        label: 'Спросить про деньги',
        child: FloatingActionButton.small(
          heroTag: 'finance-helper',
          tooltip: 'Спросить про деньги',
          onPressed: _toggle,
          child: const Text('?', style: TextStyle(fontSize: 25)),
        ),
      );
    }
    final width = min(widget.maxCardWidth, MediaQuery.sizeOf(context).width - 24);
    final height = min(widget.maxCardHeight, MediaQuery.sizeOf(context).height * .56);
    return Material(
      color: scheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('Спросить про деньги')),
                  IconButton(
                    tooltip: 'Закрыть помощника',
                    onPressed: _toggle,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _input,
                      maxLength: 180,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _ask(),
                      decoration: const InputDecoration(
                        labelText: 'Вопрос о деньгах',
                        hintText: 'Например: что такое бюджет?',
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _ask,
                      child: const Text('Спросить'),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_answer case final answer?) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(answer.text),
                      ),
                      for (final choice in answer.choices)
                        OutlinedButton(
                          onPressed: () => setState(
                            () => _answer = FinanceModelAnswer(choice.text),
                          ),
                          child: Text(choice.title),
                        ),
                      if (answer.needsChoice)
                        TextButton(
                          onPressed: () => setState(
                            () => _answer = FinanceModelAnswer(
                              _model?.policy.parentsText ??
                                  answerFinanceQuestion('').text,
                            ),
                          ),
                          child: const Text('Другое'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
