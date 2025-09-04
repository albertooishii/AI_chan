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

/// Interfaz para el controlador de llamadas de voz
/// Abstrae la lógica de manejo de llamadas en tiempo real
abstract interface class IVoiceCallController {
  /// Inicia una nueva llamada
  Future<void> startCall();

  /// Termina la llamada actual
  Future<void> endCall();

  /// Responde una llamada entrante
  Future<void> answerCall();

  /// Rechaza una llamada entrante
  Future<void> rejectCall();

  /// Silencia/des-silencia el micrófono
  void toggleMute();

  /// Estado actual del micrófono
  bool get isMuted;

  /// Envía audio al servicio
  void sendAudio(List<int> audioBytes);

  /// Obtiene el nivel de audio actual
  double get audioLevel;

  /// Stream de cambios en el estado de la llamada
  Stream<dynamic> get stateChanges;

  /// Stream de texto recibido del asistente
  Stream<String> get textStream;

  /// Stream de audio recibido del asistente
  Stream<Uint8List> get audioStream;

  /// Stream de errores
  Stream<Object> get errorStream;

  /// Libera recursos
  void dispose();
}

/// Interfaz para el manejo de audio en llamadas
/// Se usa en use cases para abstraer la implementación específica
abstract interface class IAudioManager {
  /// Configura si el micrófono está silenciado
  void setMuted(bool muted);

  /// Obtiene el estado actual del micrófono
  bool get isMuted;

  /// Stream de niveles de audio
  Stream<double> get audioLevelStream;

  /// Actualiza el nivel de audio
  void updateAudioLevel(double level);

  /// Inicializa el manejo de audio
  Future<void> initialize();

  /// Libera recursos
  void dispose();
}

/// Interfaz para el manejo de llamadas
/// Se usa en use cases para abstraer la implementación específica
abstract interface class ICallManager {
  /// Inicia una llamada
  Future<void> startCall();

  /// Termina una llamada
  Future<void> endCall();

  /// Responde una llamada entrante
  Future<void> answerIncomingCall();

  /// Rechaza una llamada entrante
  Future<void> rejectIncomingCall();

  /// Obtiene el estado actual de la llamada
  bool get isCallActive;

  /// Stream de cambios de estado de la llamada
  Stream<bool> get callStateStream;

  /// Libera recursos
  void dispose();
}
