import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/di.dart';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';

/// Cliente OpenAI Realtime adaptado para la interfaz del dominio
class OpenAIRealtimeCallClient implements IRealtimeCallClient {
  final String model;
  IRealtimeClient? _client;

  bool _connected = false;
  // Kept for parity with previous implementation and forwarded to provider.
  // ignore: unused_field
  String _voice = 'sage';
  bool _hasActiveResponse = false;
  Timer? _responseCreateTimer;
  int _bytesSinceCommit = 0;
  bool _commitScheduled = false;

  // Streams para la interfaz
  late final StreamController<String> _textController;
  late final StreamController<Uint8List> _audioController;
  late final StreamController<String> _userTranscriptionController;
  late final StreamController<Object> _errorController;
  late final StreamController<void> _completionController;

  OpenAIRealtimeCallClient({String? model})
    : model = model ?? Config.requireOpenAIRealtimeModel() {
    _textController = StreamController<String>.broadcast();
    _audioController = StreamController<Uint8List>.broadcast();
    _userTranscriptionController = StreamController<String>.broadcast();
    _errorController = StreamController<Object>.broadcast();
    _completionController = StreamController<void>.broadcast();
  }

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<Uint8List> get audioStream => _audioController.stream;

  @override
  Stream<String> get userTranscriptionStream =>
      _userTranscriptionController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;

  @override
  Future<void> connect({
    required String systemPrompt,
    String voice = 'default',
    Map<String, dynamic>? options,
  }) async {
    // API key check is performed by provider-specific clients (eg. OpenAIRealtimeClient).
    // The voice-level client should allow test-time factories to be injected via DI
    // without requiring a configured API key here.

    // Create provider-specific realtime client via DI registry.
    _client = getRealtimeClientForProvider(
      'openai',
      model: model,
      onText: (t) {
        if (t.trim().isNotEmpty) _textController.add(t.trim());
      },
      onAudio: (b) {
        try {
          _audioController.add(Uint8List.fromList(b));
        } catch (e) {
          if (kDebugMode) debugPrint('Error handling audio bytes: $e');
        }
      },
      onCompleted: () => _completionController.add(null),
      onError: (e) => _errorController.add(e),
      onUserTranscription: (s) {
        if (s.trim().isNotEmpty) _userTranscriptionController.add(s.trim());
      },
    );

    _voice = voice;
    _bytesSinceCommit = 0;

    await _client!.connect(
      systemPrompt: systemPrompt,
      voice: voice,
      options: options,
    );

    _connected = _client?.isConnected ?? false;
  }

  // Event handling is delegated to the provider-specific IRealtimeClient via
  // callbacks provided when creating the client in `connect`.

  // Low-level send is handled by the provider client.

  @override
  Future<void> disconnect() async {
    _connected = false;
    _responseCreateTimer?.cancel();

    try {
      await _client?.close();
    } catch (e) {
      if (kDebugMode) debugPrint('Error cerrando cliente realtime: $e');
    }

    _client = null;
  }

  @override
  void sendAudio(List<int> audioBytes) {
    if (!_connected) return;

    _client?.appendAudio(audioBytes);
    _bytesSinceCommit += audioBytes.length;

    // Auto-commit si hay muchos bytes pendientes
    if (_bytesSinceCommit >= 8192 && !_commitScheduled) {
      _scheduleCommit();
    }
  }

  @override
  void sendText(String text) {
    if (!_connected) return;
    _client?.sendText(text);
    requestResponse();
  }

  @override
  void updateVoice(String voice) {
    if (!_connected) return;
    _voice = voice;
    _client?.updateVoice(voice);
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    if (!_connected || _hasActiveResponse) return;

    _commitAudioBuffer();
    _hasActiveResponse = true;
    _client?.requestResponse(audio: audio, text: text);
  }

  void _scheduleCommit() {
    if (_commitScheduled) return;
    _commitScheduled = true;

    Timer(const Duration(milliseconds: 100), () {
      _commitAudioBuffer();
      _commitScheduled = false;
    });
  }

  void _commitAudioBuffer() {
    if (!_connected || _bytesSinceCommit == 0) return;

    _client?.commitPendingAudio();
    _bytesSinceCommit = 0;
  }

  /// Liberar recursos
  void dispose() {
    disconnect();
    _textController.close();
    _audioController.close();
    _userTranscriptionController.close();
    _errorController.close();
    _completionController.close();
  }
}
