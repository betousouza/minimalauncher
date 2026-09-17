/// Buffers streamed text and releases it sentence by sentence, so the
/// caller can start speaking a sentence (TTS) as soon as it is complete
/// instead of waiting for the whole response (see #22's ~1-1.5s
/// first-audio target).
class SentenceSplitter {
  static final RegExp _sentenceEnd = RegExp(r'[^.!?\n]+[.!?\n]+');

  String _buffer = '';

  /// Adds [delta] to the buffer and returns any sentences that are now
  /// complete, in order. Text without a terminator stays buffered.
  List<String> add(String delta) {
    _buffer += delta;
    final sentences = <String>[];
    var consumed = 0;
    for (final match in _sentenceEnd.allMatches(_buffer)) {
      final sentence = match.group(0)!.trim();
      if (sentence.isNotEmpty) sentences.add(sentence);
      consumed = match.end;
    }
    _buffer = _buffer.substring(consumed);
    return sentences;
  }

  /// Returns whatever is left in the buffer (a trailing sentence with no
  /// terminator yet) and clears it. Call once the stream is done.
  String flush() {
    final rest = _buffer.trim();
    _buffer = '';
    return rest;
  }
}
