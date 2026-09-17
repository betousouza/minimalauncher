import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:minimalauncher/data/jarvis_chat_client.dart';
import 'package:minimalauncher/data/jarvis_config.dart';
import 'package:minimalauncher/data/sentence_splitter.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceState { idle, listening, thinking, speaking, error }

/// Full-screen voice assistant: microphone button (#20's launcher, no wake
/// word) using the Android-native `SpeechRecognizer`/`TextToSpeech` (#22's
/// decision), talking to `POST /v1/chat/completions` (#19's contract) and
/// speaking the reply sentence by sentence as it streams in.
class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({super.key});

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final List<Map<String, String>> _messages = [];

  VoiceState _state = VoiceState.idle;
  String _liveTranscript = '';
  String _responseText = '';
  String _errorMessage = '';
  bool _speechAvailable = false;
  StreamSubscription<String>? _chatSubscription;

  /// Bumped on every new turn / cancel / failure so callbacks from a
  /// superseded turn (a late chat chunk, a late TTS completion) know to
  /// no-op instead of clobbering newer state.
  int _turn = 0;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('pt-BR');
    _tts.awaitSpeakCompletion(true);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (SpeechRecognitionError error) {
        if (_state == VoiceState.listening) {
          _fail('Erro no reconhecimento de voz: ${error.errorMsg}');
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            _state == VoiceState.listening) {
          _onListeningDone();
        }
      },
    );
    if (!mounted) return;
    setState(() => _speechAvailable = available);
    if (!available) {
      _fail('Reconhecimento de voz indisponível neste aparelho.');
    }
  }

  @override
  void dispose() {
    _turn++;
    _chatSubscription?.cancel();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  void _onMicTap() {
    switch (_state) {
      case VoiceState.idle:
      case VoiceState.error:
        _startListening();
        break;
      case VoiceState.listening:
        _speech.stop();
        break;
      case VoiceState.thinking:
      case VoiceState.speaking:
        _cancelTurn();
        break;
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _fail('Reconhecimento de voz indisponível neste aparelho.');
      return;
    }
    _turn++;
    setState(() {
      _state = VoiceState.listening;
      _liveTranscript = '';
      _responseText = '';
      _errorMessage = '';
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'pt_BR',
        cancelOnError: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveTranscript = result.recognizedWords);
      },
    );
  }

  void _onListeningDone() {
    final text = _liveTranscript.trim();
    if (text.isEmpty) {
      setState(() => _state = VoiceState.idle);
      return;
    }
    _sendToJarvis(text);
  }

  Future<void> _sendToJarvis(String text) async {
    final turn = _turn;
    setState(() {
      _state = VoiceState.thinking;
      _messages.add({'role': 'user', 'content': text});
    });

    final config = await JarvisConfig.load();
    if (turn != _turn) return;
    if (!config.isComplete) {
      _fail('Configure o servidor do Jarvis em Configurações antes de usar a voz.');
      return;
    }

    final splitter = SentenceSplitter();
    // Chains queued sentences one after another so a later sentence never
    // starts speaking before an earlier one finishes.
    var speechChain = Future<void>.value();

    void enqueueSpeech(String sentence) {
      if (sentence.isEmpty) return;
      speechChain = speechChain.then((_) {
        if (turn != _turn) return Future<void>.value();
        if (mounted) setState(() => _state = VoiceState.speaking);
        return _tts.speak(sentence);
      });
    }

    _chatSubscription = streamChatCompletion(
      config: config,
      messages: _messages,
    ).listen(
      (delta) {
        if (turn != _turn) return;
        setState(() => _responseText += delta);
        for (final sentence in splitter.add(delta)) {
          enqueueSpeech(sentence);
        }
      },
      onError: (Object error) {
        if (turn != _turn) return;
        if (error is JarvisOfflineException) {
          _fail('Sem conexão com o servidor do Jarvis. Verifique o Wi-Fi.');
        } else if (error is JarvisApiException) {
          _fail(
              'O servidor do Jarvis recusou o pedido (${error.statusCode}).');
        } else {
          _fail('Erro inesperado falando com o Jarvis.');
        }
      },
      onDone: () async {
        if (turn != _turn) return;
        enqueueSpeech(splitter.flush());
        await speechChain;
        if (turn != _turn) return;
        if (_responseText.trim().isEmpty) {
          // The server answered (200 OK) but produced no text delta at all —
          // observed when the model responds with a tool/function call that
          // the chat endpoint doesn't resolve into text. Silently going back
          // to idle here would look identical to nothing having happened.
          _fail(
              'O Jarvis não respondeu com texto a esse pedido (pode ter tentado usar uma ferramenta). Tente perguntar de outro jeito.');
          return;
        }
        _messages.add({'role': 'assistant', 'content': _responseText});
        setState(() => _state = VoiceState.idle);
      },
      cancelOnError: true,
    );
  }

  void _cancelTurn() {
    _turn++;
    _chatSubscription?.cancel();
    _tts.stop();
    if (!mounted) return;
    setState(() => _state = VoiceState.idle);
  }

  void _fail(String message) {
    _turn++;
    _chatSubscription?.cancel();
    _tts.stop();
    if (!mounted) return;
    setState(() {
      _state = VoiceState.error;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_liveTranscript.isNotEmpty ||
                          _state == VoiceState.listening)
                        Text(
                          _liveTranscript.isEmpty
                              ? 'Ouvindo...'
                              : _liveTranscript,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 20),
                        ),
                      if (_responseText.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _responseText,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 22),
                        ),
                      ],
                      if (_state == VoiceState.error) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 18),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 48.0),
              child: GestureDetector(
                onTap: _onMicTap,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _micColor(),
                  ),
                  child: Icon(_micIcon(), color: Colors.white, size: 36),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(_stateLabel(),
                  style: const TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  Color _micColor() {
    switch (_state) {
      case VoiceState.listening:
        return Colors.redAccent;
      case VoiceState.thinking:
        return Colors.orangeAccent;
      case VoiceState.speaking:
        return Colors.blueAccent;
      case VoiceState.error:
        return Colors.grey;
      case VoiceState.idle:
        return Colors.white24;
    }
  }

  IconData _micIcon() {
    switch (_state) {
      case VoiceState.thinking:
        return Icons.hourglass_top;
      case VoiceState.speaking:
        return Icons.volume_up;
      default:
        return Icons.mic;
    }
  }

  String _stateLabel() {
    switch (_state) {
      case VoiceState.idle:
        return 'Toque para falar';
      case VoiceState.listening:
        return 'Ouvindo...';
      case VoiceState.thinking:
        return 'Pensando...';
      case VoiceState.speaking:
        return 'Falando...';
      case VoiceState.error:
        return 'Toque para tentar de novo';
    }
  }
}
