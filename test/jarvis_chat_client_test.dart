import 'package:flutter_test/flutter_test.dart';
import 'package:minimalauncher/data/jarvis_chat_client.dart';

void main() {
  group('parseChatCompletionSseLine', () {
    test('ignores non-data lines (SSE blank separators)', () {
      expect(parseChatCompletionSseLine(''), isNull);
      expect(parseChatCompletionSseLine('event: message'), isNull);
    });

    test('extracts the delta content from a chunk', () {
      final line =
          'data: {"id":"1","object":"chat.completion.chunk","choices":[{"delta":{"content":"Olá"}}]}';
      expect(parseChatCompletionSseLine(line), 'Olá');
    });

    test('returns empty string for a chunk with no content delta (e.g. role-only opener)', () {
      final line =
          'data: {"id":"1","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant"}}]}';
      expect(parseChatCompletionSseLine(line), '');
    });

    test('recognizes the terminator sentinel', () {
      expect(parseChatCompletionSseLine('data: [DONE]'), sseStreamDone);
    });
  });
}
