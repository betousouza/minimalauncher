import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:minimalauncher/data/jarvis_config.dart';
import 'package:minimalauncher/variables/strings.dart';

/// Thrown when the request never reached the server (no network, DNS
/// failure, connection refused, timeout) — the case #26 requires an
/// explicit state for instead of hanging silently.
class JarvisOfflineException implements Exception {
  final String message;
  JarvisOfflineException(this.message);

  @override
  String toString() => 'JarvisOfflineException: $message';
}

/// Thrown when the server answered but rejected the request (bad auth,
/// bad model, 5xx, ...).
class JarvisApiException implements Exception {
  final int statusCode;
  final String body;
  JarvisApiException(this.statusCode, this.body);

  @override
  String toString() => 'JarvisApiException($statusCode): $body';
}

/// Parses one line of a `POST /v1/chat/completions` SSE stream (see
/// docs/research/contrato-api-servidor.md on jarvis-hub, #19). Returns:
/// - null for lines to ignore (blank lines, non-`data:` lines)
/// - '' (empty string) for a chunk with no text delta (e.g. the role-only
///   opening chunk)
/// - the sentinel below for `data: [DONE]`
/// - the delta text otherwise
const sseStreamDone = '__jarvis_sse_done__';

String? parseChatCompletionSseLine(String line) {
  if (!line.startsWith('data: ')) return null;
  final payload = line.substring(6).trim();
  if (payload.isEmpty) return null;
  if (payload == '[DONE]') return sseStreamDone;

  final decoded = jsonDecode(payload) as Map<String, dynamic>;
  final choices = decoded['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) return '';
  final delta = choices[0]['delta'] as Map<String, dynamic>?;
  final content = delta?['content'];
  return content is String ? content : '';
}

/// Streams the assistant's reply text for [messages] (OpenAI-style
/// `{role, content}` maps), one delta chunk at a time.
Stream<String> streamChatCompletion({
  required JarvisConfig config,
  required List<Map<String, String>> messages,
  http.Client? client,
}) async* {
  final httpClient = client ?? http.Client();
  try {
    final request = http.Request('POST', config.chatCompletionsUri)
      ..headers.addAll(config.headers)
      ..body = jsonEncode({
        'model': jarvisModel,
        'messages': messages,
        'stream': true,
      });

    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request).timeout(
            const Duration(seconds: 20),
          );
    } on TimeoutException {
      throw JarvisOfflineException('timeout ao conectar no servidor');
    } on SocketException catch (e) {
      throw JarvisOfflineException(e.message);
    } on http.ClientException catch (e) {
      throw JarvisOfflineException(e.message);
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw JarvisApiException(response.statusCode, body);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      final parsed = parseChatCompletionSseLine(line);
      if (parsed == null || parsed.isEmpty) continue;
      if (parsed == sseStreamDone) break;
      yield parsed;
    }
  } finally {
    if (client == null) httpClient.close();
  }
}
