import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';

/// Cliente OpenAI Realtime adaptado para la interfaz del dominio
class OpenAIRealtimeVoiceClient implements IRealtimeVoiceClient {
  final String model;

  IOWebSocketChannel? _channel;
  bool _connected = false;
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

  OpenAIRealtimeVoiceClient({String? model})
    : model = model ?? Config.requireOpenAIRealtimeModel() {
    _textController = StreamController<String>.broadcast();
    _audioController = StreamController<Uint8List>.broadcast();
    _userTranscriptionController = StreamController<String>.broadcast();
    _errorController = StreamController<Object>.broadcast();
    _completionController = StreamController<void>.broadcast();
  }

  String get _apiKey => Config.getOpenAIKey();

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
    if (_apiKey.trim().isEmpty) {
      throw Exception('Falta la API key de OpenAI.');
    }

    final uri = Uri.parse('wss://api.openai.com/v1/realtime?model=$model');

    if (kDebugMode) {
      debugPrint('Realtime: conectando con modelo=$model');
    }

    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'OpenAI-Beta': 'realtime=v1',
      },
    );
    _connected = true;
    _bytesSinceCommit = 0;
    _voice = voice;

    final sessionReady = Completer<void>();

    // Escuchar mensajes
    _channel!.stream.listen(
      (data) {
        try {
          final evt = jsonDecode(data as String) as Map<String, dynamic>;
          _handleEvent(evt, sessionReady);
        } catch (e) {
          _errorController.add(e);
        }
      },
      onError: (e) {
        _errorController.add(e);
        _connected = false;
      },
      onDone: () {
        _connected = false;
      },
    );

    // Esperar a que la sesión esté creada
    try {
      await sessionReady.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Realtime: timeout esperando session.created');
      }
    }
  }

  void _handleEvent(Map<String, dynamic> evt, Completer<void> sessionReady) {
    final type = evt['type'] as String? ?? '';

    // Manejar texto recibido
    if (type.startsWith('response.text.') && evt['text'] is String) {
      final text = (evt['text'] as String).trim();
      if (text.isNotEmpty) _textController.add(text);
    }

    if (type.startsWith('response.audio_transcript.') &&
        evt['delta'] is String) {
      final tx = (evt['delta'] as String).trim();
      if (tx.isNotEmpty) _textController.add(tx);
    }

    if (type == 'response.audio_transcript.done') {
      final t = (evt['transcript'] ?? '').toString();
      if (t.isNotEmpty) _textController.add(t);
    }

    // Manejar audio recibido
    if (type.startsWith('response.audio.') && evt['delta'] is String) {
      try {
        final audioData = base64Decode(evt['delta'] as String);
        _audioController.add(Uint8List.fromList(audioData));
      } catch (e) {
        if (kDebugMode) debugPrint('Error decodificando audio: $e');
      }
    }

    // Manejar transcripciones del usuario
    if (type.startsWith('conversation.item.input_audio_transcription.')) {
      final transcript = evt['transcript'] as String? ?? '';
      if (transcript.trim().isNotEmpty) {
        _userTranscriptionController.add(transcript.trim());
      }
    }

    // Manejar eventos de sesión
    if (type == 'session.created' && !sessionReady.isCompleted) {
      if (kDebugMode) {
        debugPrint(
          'Realtime: session.created recibido, aplicando voice="$_voice"',
        );
      }
      _send({
        'type': 'session.update',
        'session': {
          'instructions': '',
          'modalities': ['audio', 'text'],
          'voice': _voice,
        },
      });
      sessionReady.complete();
    }

    // Manejar finalización de respuesta
    if (type == 'response.done') {
      _hasActiveResponse = false;
      _completionController.add(null);
    }

    // Manejar errores
    if (type == 'error') {
      final error = evt['error'] ?? {};
      final message = error['message'] ?? 'Unknown error';
      _errorController.add(Exception('OpenAI Realtime Error: $message'));
    }
  }

  void _send(Map<String, dynamic> event) {
    if (!_connected || _channel == null) return;

    try {
      final jsonData = jsonEncode(event);
      _channel!.sink.add(jsonData);

      if (kDebugMode && event['type'] != 'input_audio_buffer.append') {
        debugPrint('Realtime -> ${event['type']}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error enviando evento: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _responseCreateTimer?.cancel();

    try {
      await _channel?.sink.close();
    } catch (e) {
      if (kDebugMode) debugPrint('Error cerrando canal: $e');
    }

    _channel = null;
  }

  @override
  void sendAudio(List<int> audioBytes) {
    if (!_connected) return;

    final audioBase64 = base64Encode(audioBytes);
    _send({'type': 'input_audio_buffer.append', 'audio': audioBase64});

    _bytesSinceCommit += audioBytes.length;

    // Auto-commit si hay muchos bytes pendientes
    if (_bytesSinceCommit >= 8192 && !_commitScheduled) {
      _scheduleCommit();
    }
  }

  @override
  void sendText(String text) {
    if (!_connected) return;
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
        ],
      },
    });
    requestResponse();
  }

  @override
  void updateVoice(String voice) {
    if (!_connected) return;
    _voice = voice;
    _send({
      'type': 'session.update',
      'session': {'voice': voice},
    });
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    if (!_connected || _hasActiveResponse) return;

    _commitAudioBuffer();
    _hasActiveResponse = true;

    _send({
      'type': 'response.create',
      'response': {
        'modalities': [if (audio) 'audio', if (text) 'text'],
      },
    });
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

    _send({'type': 'input_audio_buffer.commit'});
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
