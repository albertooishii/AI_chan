import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';
import 'package:ai_chan/shared/utils/debug_call_logger/debug_call_logger.dart';

/// Cliente Gemini que emula tiempo real usando STT/TTS separados
class GeminiRealtimeVoiceClient implements IRealtimeVoiceClient {
  final String model;

  bool _connected = false;
  final List<int> _pendingAudio = [];
  Timer? _deferredTranscribeTimer;
  String? _systemPromptRaw;

  // Streams para la interfaz
  late final StreamController<String> _textController;
  late final StreamController<Uint8List> _audioController;
  late final StreamController<String> _userTranscriptionController;
  late final StreamController<Object> _errorController;
  late final StreamController<void> _completionController;

  GeminiRealtimeVoiceClient({String? model}) : model = model ?? Config.requireGoogleRealtimeModel() {
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
  Stream<String> get userTranscriptionStream => _userTranscriptionController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;

  @override
  Future<void> connect({required String systemPrompt, String voice = 'default', Map<String, dynamic>? options}) async {
    _connected = true;
    // Gemini simula la conexión - no hay conexión WebSocket real
    // Guardar el systemPrompt para reenviarlo en mensajes posteriores y mantener contexto
    _systemPromptRaw = systemPrompt;
    if (kDebugMode) {
      debugPrint('GeminiRealtime: "conectado" con modelo=$model (systemPromptLen=${systemPrompt.length})');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _deferredTranscribeTimer?.cancel();
    _pendingAudio.clear();
    _systemPromptRaw = null;
    if (kDebugMode) {
      debugPrint('GeminiRealtime: desconectado');
    }
  }

  @override
  void sendAudio(List<int> audioBytes) {
    if (!_connected) return;

    _pendingAudio.addAll(audioBytes);
    _deferredTranscribeTimer?.cancel();
    _deferredTranscribeTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        await _processPendingAudioChunk();
      } catch (e) {
        _errorController.add(e);
        if (kDebugMode) debugPrint('GeminiRealtime: STT error $e');
      }
    });
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
    // If we have pending audio, process it (STT -> send to Gemini)
    if (_pendingAudio.isNotEmpty) {
      _processPendingAudioChunk();
      return;
    }

    // If caller explicitly requested audio, ask the model to respond now in
    // natural speech (no control tags). This avoids the model replying only
    // with control tags when we expect a spoken response.
    if (audio) {
      final acceptPrompt =
          'El usuario ha aceptado la llamada. NO respondas con etiquetas de control. RESPONDE AHORA en voz natural y proporciona un saludo breve (una o dos frases).';
      _sendTranscriptToGemini(acceptPrompt).catchError((e) {
        _errorController.add(e);
      });
      return;
    }

    // If text-only requested, send the incoming call notice so the model may
    // emit control tags (phase 1)
    if (text && _systemPromptRaw != null && _systemPromptRaw!.trim().isNotEmpty) {
      final incomingCallNotice =
          'El usuario ha iniciado una llamada. Responde SOLO con "[start_call][/start_call]" para aceptar o "[end_call][/end_call]" para rechazar.';
      _sendTranscriptToGemini(incomingCallNotice).catchError((e) {
        _errorController.add(e);
      });
      return;
    }

    // Nothing to do otherwise
    return;
  }

  /// Procesa el audio pendiente usando STT
  Future<void> _processPendingAudioChunk() async {
    if (_pendingAudio.isEmpty) return;

    final data = List<int>.from(_pendingAudio);
    _pendingAudio.clear();

    try {
      // Crear archivo temporal para STT
      final tmpDir = await Directory.systemTemp.createTemp('gemini_stt');
      final tmpFile = File('${tmpDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav');
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

      // Construir payload de mensajes. Si tenemos systemPromptRaw disponible,
      // incluirlo como un bloque con role='model' para que Gemini reciba el contexto
      // explícito cada vez (evita que el modelo "olvide" las instrucciones de llamada).
      final List<Map<String, String>> messages = [];
      if (_systemPromptRaw != null && _systemPromptRaw!.trim().isNotEmpty) {
        messages.add({'role': 'model', 'content': _systemPromptRaw!});
      }
      messages.add({'role': 'user', 'content': transcript});

      // Si el transcript parece ser el mensaje de aceptación enviado por el controlador,
      // añadir una instrucción explícita para que el modelo responda con saludo en texto
      // y NO repita las etiquetas de control. Esto refuerza la intención cuando Gemini
      // tiende a devolver solo las etiquetas.
      final lower = transcript.toLowerCase();
      if (lower.contains('acept') || lower.contains('aceptado') || lower.contains('aceptar la llamada')) {
        messages.add({
          'role': 'user',
          'content':
              'IMPORTANTE: Ahora responde en texto natural sin usar las etiquetas [start_call] ni [end_call]. Proporciona un saludo breve (1-2 frases) y continúa la conversación. Esto será sintetizado a audio.',
        });
      }

      // Enviar mensaje y obtener respuesta
      final respMap = await ai.sendMessage(
        messages: messages,
        options: {'model': model, 'systemPromptRawIncluded': true},
      );

      final text = (respMap['text'] ?? respMap['response'] ?? '')?.toString() ?? '';

      if (text.isNotEmpty) {
        // Emitir texto recibido
        _textController.add(text);

        try {
          final hasEnd = RegExp(r'\[\/?end_call\]').hasMatch(text);
          final clean = text
              .replaceAll(RegExp(r'\[\/?start_call\]'), '')
              .replaceAll(RegExp(r'\[\/?end_call\]'), '')
              .trim();

          if (hasEnd && clean.isEmpty) {
            try {
              await debugLogCallPrompt('gemini_realtime_control_tag', {'tag': '[end_call][/end_call]'});
            } catch (_) {}
            _textController.add('[end_call][/end_call]');
            return;
          }

          if (clean.isEmpty) return;

          final ITtsService tts = di.getTtsServiceForProvider('google');
          try {
            final filePath = await tts.synthesizeToFile(
              text: clean,
              options: {'audioEncoding': 'LINEAR16', 'sampleRateHertz': 24000, 'format': 'wav', 'noCache': true},
            );
            if (filePath != null && filePath.isNotEmpty) {
              try {
                final bytes = await File(filePath).readAsBytes();
                final wav = Uint8List.fromList(bytes);
                final pcm = _extractPcmFromWav(wav);
                _audioController.add(pcm);
              } catch (e) {
                if (kDebugMode) debugPrint('GeminiRealtime: failed reading TTS file $e');
              } finally {
                try {
                  final f = File(filePath);
                  if (await f.exists()) await f.delete();
                } catch (_) {}
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('GeminiRealtime: TTS error $e');
          }
        } catch (_) {}
      }

      // Notificar finalización de respuesta
      _completionController.add(null);
    } catch (e) {
      _errorController.add(e);
    }
  }

  Uint8List _extractPcmFromWav(Uint8List bytes) {
    try {
      for (int i = 0; i < bytes.length - 4; i++) {
        if (bytes[i] == 0x64 && bytes[i + 1] == 0x61 && bytes[i + 2] == 0x74 && bytes[i + 3] == 0x61) {
          final size =
              (bytes[i + 4] & 0xFF) |
              ((bytes[i + 5] & 0xFF) << 8) |
              ((bytes[i + 6] & 0xFF) << 16) |
              ((bytes[i + 7] & 0xFF) << 24);
          final dataStart = i + 8;
          final dataEnd = (dataStart + size) <= bytes.length ? dataStart + size : bytes.length;
          return bytes.sublist(dataStart, dataEnd);
        }
      }
    } catch (_) {}
    return bytes;
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
