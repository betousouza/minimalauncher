import 'package:flutter_test/flutter_test.dart';
import 'package:minimalauncher/data/sentence_splitter.dart';

void main() {
  group('SentenceSplitter', () {
    test('buffers text with no terminator yet', () {
      final splitter = SentenceSplitter();
      expect(splitter.add('Olá, tudo'), isEmpty);
    });

    test('releases a sentence once it sees a terminator', () {
      final splitter = SentenceSplitter();
      expect(splitter.add('Olá, tudo bem?'), ['Olá, tudo bem?']);
    });

    test('splits multiple sentences delivered in one chunk', () {
      final splitter = SentenceSplitter();
      expect(
        splitter.add('Oi! Como vai? Tudo certo.'),
        ['Oi!', 'Como vai?', 'Tudo certo.'],
      );
    });

    test('keeps trailing partial sentence buffered across chunks', () {
      final splitter = SentenceSplitter();
      expect(splitter.add('A previsão é de chuva'), isEmpty);
      expect(splitter.add(' hoje. Amanhã abre o sol'), ['A previsão é de chuva hoje.']);
      expect(splitter.flush(), 'Amanhã abre o sol');
    });

    test('flush returns empty string when nothing is buffered', () {
      final splitter = SentenceSplitter();
      splitter.add('Feito.');
      expect(splitter.flush(), '');
    });
  });
}
