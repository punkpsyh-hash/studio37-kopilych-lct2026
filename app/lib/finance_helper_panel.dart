import 'dart:math';

import 'package:flutter/material.dart';

import 'finance_helper.dart';
import 'finance_helper_model.dart';
import 'finance_helper_model_policy.dart';

/// Keeps the question form mounted when the keyboard changes the game HUD.
class FinanceHelperPage extends StatelessWidget {
  const FinanceHelperPage({super.key, this.loadModel = FinanceHelperModel.load});

  final Future<FinanceHelperModel> Function() loadModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Помощник по деньгам')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: FinanceHelperPanel(
            initiallyOpen: true,
            loadModel: loadModel,
            maxCardWidth: 430,
            maxCardHeight: 520,
          ),
        ),
      ),
    ),
  );
}

/// Compact floating help UI. Place in a Stack above the full-screen room.
class FinanceHelperPanel extends StatefulWidget {
  const FinanceHelperPanel({
    super.key,
    this.loadModel = FinanceHelperModel.load,
    this.maxCardWidth = 350,
    this.maxCardHeight = 430,
    this.initiallyOpen = false,
  });

  final Future<FinanceHelperModel> Function() loadModel;
  final double maxCardWidth;
  final double maxCardHeight;
  final bool initiallyOpen;

  @override
  State<FinanceHelperPanel> createState() => _FinanceHelperPanelState();
}

class _FinanceHelperPanelState extends State<FinanceHelperPanel> {
  final _input = TextEditingController();
  FinanceHelperModel? _model;
  FinanceModelAnswer? _answer;
  bool _busy = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyOpen) _loadModel();
  }

  void _loadModel() {
    widget.loadModel().then((model) {
      if (mounted) setState(() => _model = model);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _epoch++;
    _input.dispose();
    super.dispose();
  }

  void _openPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinanceHelperPage(loadModel: widget.loadModel),
      ),
    );
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
    if (!widget.initiallyOpen) {
      return Semantics(
        button: true,
        label: 'Спросить про деньги',
        child: FloatingActionButton.small(
          heroTag: 'finance-helper',
          tooltip: 'Спросить про деньги',
          onPressed: _openPage,
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
                    onPressed: () => Navigator.of(context).pop(),
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
