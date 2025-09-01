import 'dart:typed_data';

import 'package:ai_chan/call/domain/models/call.dart';
import 'package:ai_chan/call/domain/models/call_message.dart';

/// Repositorio para persistir y recuperar llamadas
abstract interface class ICallRepository {
  /// Guarda una llamada
  Future<void> saveCall(Call call);

  /// Recupera una llamada por ID
  Future<Call?> getCall(String id);

  /// Recupera todas las llamadas
  Future<List<Call>> getAllCalls();

  /// Recupera llamadas por rango de fechas
  Future<List<Call>> getCallsByDateRange(DateTime from, DateTime to);

  /// Elimina una llamada
  Future<void> deleteCall(String id);

  /// Elimina todas las llamadas
  Future<void> deleteAllCalls();

  /// Actualiza una llamada existente
  Future<void> updateCall(Call call);

  /// Agrega un mensaje a una llamada existente
  Future<void> addMessageToCall(String callId, CallMessage message);

  /// Obtiene el historial de mensajes de una llamada
  Future<List<CallMessage>> getCallMessages(String callId);
}

// Nota: Las interfaces IVoiceSttService, IVoiceTtsService e IVoiceAiService
// fueron eliminadas para reducir sobre-abstracción. Se usan directamente:
// - ISttService de core/interfaces/i_stt_service.dart
// - ITtsService de core/interfaces/tts_service.dart
// - IAIService de core/interfaces/ai_service.dart

/// Cliente de tiempo real para comunicación bidireccional
abstract interface class IRealtimeCallClient {
  /// Conecta al servicio de tiempo real
  Future<void> connect({required String systemPrompt, String voice = 'default', Map<String, dynamic>? options});

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
