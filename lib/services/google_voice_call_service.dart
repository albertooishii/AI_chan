import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../interfaces/voice_services.dart';
import 'implementations/google_speech_implementations.dart';
import 'implementations/gemini_conversational_service.dart';
import '../utils/log_utils.dart';

/// Servicio completo de voz de Google usando Gemini AI + Google Cloud TTS/STT
class GoogleVoiceCallService implements VoiceCallService {
  // Servicios desacoplados
  final TTSService _ttsService;
  final STTService _sttService;
  final ConversationalAIService _aiService;

  // Streams de comunicación
  StreamController<String>? _textStreamController;
  StreamController<Uint8List>? _audioStreamController;

  // Estado de la llamada
  List<Map<String, String>> _conversationHistory = [];
  bool _isCallActive = false;
  Map<String, dynamic>? _callConfig;

  // Constructor con servicios inyectados (Dependency Injection)
  GoogleVoiceCallService({TTSService? ttsService, STTService? sttService, ConversationalAIService? aiService})
    : _ttsService = ttsService ?? GoogleTTSService(),
      _sttService = sttService ?? GoogleSTTService(),
      _aiService = aiService ?? GeminiConversationalAIService();

  @override
  Stream<String> get textStream => _textStreamController?.stream ?? const Stream.empty();

  @override
  Stream<Uint8List> get audioStream => _audioStreamController?.stream ?? const Stream.empty();

  @override
  bool get isCallActive => _isCallActive;

  @override
  List<Map<String, String>> get conversationHistory => List.unmodifiable(_conversationHistory);

  @override
  Future<bool> startCall({required Map<String, dynamic> config}) async {
    if (_isCallActive) {
      Log.w('[GoogleVoice] Ya hay una sesión activa');
      return false;
    }

    Log.i('[GoogleVoice] 🚀 Iniciando llamada con Google Voice: Gemini AI + Google Cloud TTS/STT');

    // Verificar que todos los servicios estén disponibles
    if (!_ttsService.isAvailable) {
      Log.e('[GoogleVoice] ❌ Servicio TTS no disponible');
      return false;
    }

    if (!_sttService.isAvailable) {
      Log.e('[GoogleVoice] ❌ Servicio STT no disponible');
      return false;
    }

    if (!_aiService.isAvailable) {
      Log.e('[GoogleVoice] ❌ Servicio de IA no disponible');
      return false;
    }

    try {
      // Inicializar streams
      _textStreamController = StreamController<String>.broadcast();
      _audioStreamController = StreamController<Uint8List>.broadcast();

      // Limpiar estado
      _conversationHistory.clear();
      _callConfig = Map.from(config);
      _isCallActive = true;

      // Configurar system prompt si se proporciona
      if (config.containsKey('systemPrompt')) {
        // El system prompt se aplicará cuando se envíe el primer mensaje
        Log.d('[GoogleVoice] System prompt configurado desde parámetros');
      }

      // Log de configuración
      Log.i('[GoogleVoice] ✅ Configuración:');
      Log.i('  🎤 STT: ${_sttService.runtimeType}');
      Log.i('  🔊 TTS: ${_ttsService.runtimeType}');
      Log.i('  🤖 AI: ${_aiService.runtimeType}');
      Log.i('  📋 Config: ${_ttsService.getConfig()}');

      // Mensaje de bienvenida (opcional)
      if (config['welcomeMessage'] == true) {
        await _sendWelcomeMessage();
      }

      Log.i('[GoogleVoice] 🎉 Llamada con Google Voice iniciada correctamente');
      return true;
    } catch (e) {
      Log.e('[GoogleVoice] ❌ Error iniciando llamada: $e');
      await _cleanup();
      return false;
    }
  }

  @override
  Future<void> processUserAudio(Uint8List audioData) async {
    if (!_isCallActive) {
      Log.w('[GoogleVoice] No hay llamada activa para procesar audio');
      return;
    }

    try {
      Log.d('[GoogleVoice] 🎤 Procesando audio del usuario (${audioData.length} bytes)');

      // Configuración STT desde las variables de entorno
      final sttOptions = {
        'languageCode': dotenv.env['GOOGLE_LANGUAGE_CODE'] ?? 'es-ES',
        'audioEncoding': 'WEBM_OPUS',
        'sampleRateHertz': 48000,
        'enableAutomaticPunctuation': true,
      };

      // Convertir audio a texto
      final transcript = await _sttService.speechToText(audioData: audioData, options: sttOptions);

      if (transcript != null && transcript.trim().isNotEmpty) {
        Log.i('[GoogleVoice] 📝 Transcripción: "$transcript"');

        // Procesar como texto
        await processUserText(transcript);
      } else {
        Log.w('[GoogleVoice] ⚠️ No se pudo transcribir el audio o estaba vacío');
      }
    } catch (e) {
      Log.e('[GoogleVoice] ❌ Error procesando audio del usuario: $e');
    }
  }

  @override
  Future<void> processUserText(String text) async {
    if (!_isCallActive) {
      Log.w('[GoogleVoice] No hay llamada activa para procesar texto');
      return;
    }

    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      Log.w('[GoogleVoice] Texto vacío ignorado');
      return;
    }

    try {
      Log.i('[GoogleVoice] 💬 Procesando texto del usuario: "$cleanText"');

      // Agregar mensaje del usuario al historial
      _conversationHistory.add({'role': 'user', 'content': cleanText});

      // Generar respuesta con la IA
      await _generateAIResponse(cleanText);
    } catch (e) {
      Log.e('[GoogleVoice] ❌ Error procesando texto del usuario: $e');
    }
  }

  /// Genera respuesta de IA y la convierte a audio
  Future<void> _generateAIResponse(String userMessage) async {
    try {
      Log.d('[GoogleVoice] 🤖 Generando respuesta con IA...');

      // Generar respuesta usando el servicio de IA
      final response = await _aiService.sendMessage(
        message: userMessage,
        conversationHistory: _conversationHistory
            .take(_conversationHistory.length - 1)
            .toList(), // Excluir el último mensaje que ya está incluido
        context: _callConfig,
      );

      if (response.isNotEmpty) {
        Log.i('[GoogleVoice] 💭 Respuesta de IA: "$response"');

        // Emitir texto al stream
        _textStreamController?.add(response);

        // Agregar respuesta de IA al historial
        _conversationHistory.add({'role': 'assistant', 'content': response});

        // Convertir respuesta a audio
        await _convertResponseToAudio(response);
      } else {
        Log.w('[GoogleVoice] ⚠️ La IA generó una respuesta vacía');
      }
    } catch (e) {
      Log.e('[GoogleVoice] ❌ Error generando respuesta de IA: $e');

      // Respuesta de fallback
      const fallbackResponse = 'Lo siento, tuve un problema procesando tu mensaje.';
      _textStreamController?.add(fallbackResponse);
      await _convertResponseToAudio(fallbackResponse);
    }
  }

  /// Convierte texto a audio y lo emite al stream
  Future<void> _convertResponseToAudio(String text) async {
    try {
      Log.d('[GoogleVoice] 🔊 Convirtiendo texto a audio...');

      // Configuración TTS desde las variables de entorno
      final ttsOptions = _ttsService.getConfig();

      // Generar audio
      final audioData = await _ttsService.textToSpeech(text: text, options: ttsOptions);

      if (audioData != null) {
        Log.i('[GoogleVoice] 🎵 Audio generado exitosamente: ${audioData.length} bytes');

        // Emitir audio al stream
        _audioStreamController?.add(audioData);
      } else {
        Log.e('[GoogleVoice] ❌ Error generando audio');
      }
    } catch (e) {
      Log.e('[GoogleVoice] ❌ Error convirtiendo texto a audio: $e');
    }
  }

  /// Envía mensaje de bienvenida
  Future<void> _sendWelcomeMessage() async {
    const welcomeText = '¡Hola! Soy AI-chan, tu asistente virtual. ¿En qué puedo ayudarte hoy?';

    Log.i('[GoogleVoice] 👋 Enviando mensaje de bienvenida');

    // Emitir texto de bienvenida
    _textStreamController?.add(welcomeText);

    // Agregar al historial
    _conversationHistory.add({'role': 'assistant', 'content': welcomeText});

    // Convertir a audio
    await _convertResponseToAudio(welcomeText);
  }

  @override
  Future<void> stopCall() async {
    if (!_isCallActive) {
      Log.w('[GoogleVoice] No hay llamada activa que detener');
      return;
    }

    Log.i('[GoogleVoice] 🛑 Deteniendo llamada con Google Voice');

    await _cleanup();

    Log.i('[GoogleVoice] ✅ Llamada con Google Voice detenida completamente');
  }

  /// Limpia recursos y estado
  Future<void> _cleanup() async {
    _isCallActive = false;

    try {
      await _textStreamController?.close();
      await _audioStreamController?.close();
    } catch (e) {
      Log.e('[GoogleVoice] Error cerrando streams: $e');
    }

    _textStreamController = null;
    _audioStreamController = null;
    _conversationHistory.clear();
    _callConfig = null;
  }

  /// Obtiene estadísticas de la llamada
  Map<String, dynamic> getCallStats() {
    return {
      'isActive': _isCallActive,
      'messageCount': _conversationHistory.length,
      'servicesAvailable': {
        'tts': _ttsService.isAvailable,
        'stt': _sttService.isAvailable,
        'ai': _aiService.isAvailable,
      },
      'config': _callConfig,
    };
  }

  /// Verifica si todos los servicios están disponibles
  bool get allServicesAvailable => _ttsService.isAvailable && _sttService.isAvailable && _aiService.isAvailable;
}
