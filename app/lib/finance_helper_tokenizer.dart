/// WordPiece tokenization for the exported local finance intent classifier.
/// This file does not load or execute the ONNX model.
class FinanceHelperTokenizer {
  FinanceHelperTokenizer(List<String> vocabulary, {this.maxLength = 48})
    : _ids = {for (var i = 0; i < vocabulary.length; i++) vocabulary[i]: i};

  final Map<String, int> _ids;
  final int maxLength;

  List<int> encode(String question) {
    final cls = _required('[CLS]');
    final sep = _required('[SEP]');
    final unknown = _required('[UNK]');
    final result = <int>[cls];
    final normalized = question
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('й', 'и')
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), ' ');
    final words = normalized
        .replaceAll('-', ' - ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    for (final word in words) {
      if (result.length >= maxLength - 1) break;
      if (word.runes.length > 100) {
        result.add(unknown);
        continue;
      }
      final units = word.runes.map(String.fromCharCode).toList();
      final pieces = <int>[];
      var start = 0;
      while (start < units.length) {
        int? found;
        var end = units.length;
        while (end > start) {
          final piece = '${start == 0 ? '' : '##'}${units.sublist(start, end).join()}';
          found = _ids[piece];
          if (found != null) break;
          end--;
        }
        if (found == null) {
          pieces.clear();
          pieces.add(unknown);
          break;
        }
        pieces.add(found);
        start = end;
      }
      result.addAll(pieces.take(maxLength - 1 - result.length));
    }
    result.add(sep);
    return result;
  }

  int _required(String token) =>
      _ids[token] ?? (throw StateError('Missing tokenizer token $token'));
}
