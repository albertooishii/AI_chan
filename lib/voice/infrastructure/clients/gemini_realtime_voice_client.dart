import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';

/// Cliente Gemini que emula tiempo real usando STT/TTS separados
class GeminiRealtimeVoiceClient implements IRealtimeVoiceClient {
  final String model;

  bool _connected = false;
  final List<int> _pendingAudio = [];
  Timer? _deferredTranscribeTimer;

  // Streams para la interfaz
  late final StreamController<String> _textController;
  late final StreamController<Uint8List> _audioController;
  late final StreamController<String> _userTranscriptionController;
  late final StreamController<Object> _errorController;
  late final StreamController<void> _completionController;

  GeminiRealtimeVoiceClient({String? model})
    : model = model ?? Config.requireGoogleRealtimeModel() {
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
    _connected = true;
    // Gemini simula la conexión - no hay conexión WebSocket real
    if (kDebugMode) {
      debugPrint('GeminiRealtime: "conectado" con modelo=$model');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _deferredTranscribeTimer?.cancel();
    _pendingAudio.clear();
    if (kDebugMode) {
      debugPrint('GeminiRealtime: desconectado');
    }
  }

  @override
  void sendAudio(List<int> audioBytes) {
    if (!_connected) return;

    _pendingAudio.addAll(audioBytes);
    _deferredTranscribeTimer?.cancel();
    _deferredTranscribeTimer = Timer(
      const Duration(milliseconds: 300),
      () async {
        try {
          await _processPendingAudioChunk();
        } catch (e) {
          _errorController.add(e);
          if (kDebugMode) debugPrint('GeminiRealtime: STT error $e');
        }
      },
    );
  }

  @override
  void sendText(String text) {
    if (!_connected) return;

    // Procesar directamente el texto sin STT
    _userTranscriptionController.add(text);
    _sendTranscriptToGemini(text);
  }

  @override
  void updateVoice(String voice) {
    // Gemini puede cambiar voz para próximas respuestas TTS
    if (kDebugMode) {
      debugPrint('GeminiRealtime: actualizando voz a $voice');
    }
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    _deferredTranscribeTimer?.cancel();
    _processPendingAudioChunk();
  }

  /// Procesa el audio pendiente usando STT
  Future<void> _processPendingAudioChunk() async {
    if (_pendingAudio.isEmpty) return;

    final data = List<int>.from(_pendingAudio);
    _pendingAudio.clear();

    try {
      // Crear archivo temporal para STT
      final tmpDir = await Directory.systemTemp.createTemp('gemini_stt');
      final tmpFile = File(
        '${tmpDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await tmpFile.writeAsBytes(data);

      // Usar adaptador STT de Google
      final ISttService stt = di.getSttServiceForProvider('google');
      final text = await stt.transcribeAudio(tmpFile.path);

      try {
        await tmpFile.delete();
        await tmpDir.delete();
      } catch (_) {}

      if (text != null && text.trim().isNotEmpty) {
        _userTranscriptionController.add(text.trim());
        await _sendTranscriptToGemini(text.trim());
      }
    } catch (e) {
      _errorController.add(e);
    }
  }

  /// Envía el texto transcrito a Gemini y procesa la respuesta
  Future<void> _sendTranscriptToGemini(String transcript) async {
    try {
      // Usar servicio de IA configurado para el modelo
      final IAIService ai = di.getAIServiceForModel(model);

      // Enviar mensaje y obtener respuesta
      final respMap = await ai.sendMessage(
        messages: [
          {'role': 'user', 'content': transcript},
        ],
        options: {'model': model},
      );

      final text =
          (respMap['text'] ?? respMap['response'] ?? '')?.toString() ?? '';

      if (text.isNotEmpty) {
        // Emitir texto recibido
        _textController.add(text);

        // Generar audio usando TTS de Google
        final ITtsService tts = di.getTtsServiceForProvider('google');
        try {
          final filePath = await tts.synthesizeToFile(text: text);
          if (filePath != null && filePath.isNotEmpty) {
            try {
              final bytes = await File(filePath).readAsBytes();
              _audioController.add(Uint8List.fromList(bytes));
            } catch (e) {
              if (kDebugMode) {
                debugPrint('GeminiRealtime: failed reading TTS file $e');
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('GeminiRealtime: TTS error $e');
        }
      }

      // Notificar finalización de respuesta
      _completionController.add(null);
    } catch (e) {
      _errorController.add(e);
    }
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
