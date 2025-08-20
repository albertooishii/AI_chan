import 'dart:typed_data';

import 'package:ai_chan/voice/domain/models/voice_call.dart';
import 'package:ai_chan/voice/domain/models/voice_message.dart';

/// Repositorio para persistir y recuperar llamadas de voz
abstract interface class IVoiceCallRepository {
  /// Guarda una llamada de voz
  Future<void> saveCall(VoiceCall call);

  /// Recupera una llamada por ID
  Future<VoiceCall?> getCall(String id);

  /// Recupera todas las llamadas
  Future<List<VoiceCall>> getAllCalls();

  /// Recupera llamadas por rango de fechas
  Future<List<VoiceCall>> getCallsByDateRange(DateTime from, DateTime to);

  /// Elimina una llamada
  Future<void> deleteCall(String id);

  /// Elimina todas las llamadas
  Future<void> deleteAllCalls();

  /// Actualiza una llamada existente
  Future<void> updateCall(VoiceCall call);

  /// Agrega un mensaje a una llamada existente
  Future<void> addMessageToCall(String callId, VoiceMessage message);

  /// Obtiene el historial de mensajes de una llamada
  Future<List<VoiceMessage>> getCallMessages(String callId);
}

/// Servicio de Speech-to-Text para convertir audio a texto
abstract interface class IVoiceSttService {
  /// Convierte audio a texto desde datos binarios
  Future<String?> transcribeFromBytes(
    Uint8List audioData, {
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  });

  /// Convierte audio a texto desde archivo
  Future<String?> transcribeFromFile(
    String audioFilePath, {
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  });

  /// Verifica si el servicio está disponible
  bool get isAvailable;

  /// Obtiene los idiomas soportados
  Future<List<String>> getSupportedLanguages();
}

/// Servicio de Text-to-Speech para convertir texto a audio
abstract interface class IVoiceTtsService {
  /// Convierte texto a audio y lo guarda en archivo
  Future<String?> synthesizeToFile({
    required String text,
    String voice = 'sage',
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  });

  /// Convierte texto a audio y devuelve bytes
  Future<Uint8List?> synthesizeToBytes({
    required String text,
    String voice = 'sage',
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  });

  /// Obtiene las voces disponibles
  Future<List<Map<String, dynamic>>> getAvailableVoices();

  /// Verifica si el servicio está disponible
  bool get isAvailable;

  /// Obtiene los idiomas soportados
  Future<List<String>> getSupportedLanguages();
}

/// Servicio de IA conversacional para generar respuestas
abstract interface class IVoiceAiService {
  /// Envía un mensaje y recibe una respuesta
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? options,
  });

  /// Verifica si el servicio está disponible
  bool get isAvailable;

  /// Obtiene los modelos disponibles
  Future<List<String>> getAvailableModels();
}

/// Cliente de tiempo real para comunicación bidireccional
abstract interface class IRealtimeVoiceClient {
  /// Conecta al servicio de tiempo real
  Future<void> connect({
    required String systemPrompt,
    String voice = 'default',
    Map<String, dynamic>? options,
  });

  /// Desconecta del servicio
  Future<void> disconnect();

  /// Verifica si está conectado
  bool get isConnected;

  /// Envía audio al servicio
  void sendAudio(List<int> audioBytes);

  /// Envía texto al servicio
  void sendText(String text);

  /// Actualiza la voz en tiempo real
  void updateVoice(String voice);

  /// Solicita una respuesta del asistente
  void requestResponse({bool audio = true, bool text = true});

  /// Stream de texto recibido del asistente
  Stream<String> get textStream;

  /// Stream de audio recibido del asistente
  Stream<Uint8List> get audioStream;

  /// Stream de transcripciones del usuario
  Stream<String> get userTranscriptionStream;

  /// Stream de errores
  Stream<Object> get errorStream;

  /// Callback cuando se completa una respuesta
  Stream<void> get completionStream;
}
