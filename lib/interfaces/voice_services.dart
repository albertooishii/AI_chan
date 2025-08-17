import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Interface abstracta para servicios de texto a voz (TTS)
abstract class TTSService {
  /// Convierte texto a audio en bytes
  Future<Uint8List?> textToSpeech({required String text, Map<String, dynamic>? options});

  /// Convierte texto a audio y lo guarda como archivo
  Future<File?> textToSpeechFile({required String text, String? fileName, Map<String, dynamic>? options});

  /// Verifica si el servicio está disponible y configurado
  bool get isAvailable;

  /// Obtiene configuración del servicio
  Map<String, dynamic> getConfig();
}

/// Interface abstracta para servicios de voz a texto (STT)
abstract class STTService {
  /// Convierte audio a texto
  Future<String?> speechToText({required Uint8List audioData, Map<String, dynamic>? options});

  /// Convierte un archivo de audio a texto
  Future<String?> speechToTextFromFile({required File audioFile, Map<String, dynamic>? options});

  /// Verifica si el servicio está disponible y configurado
  bool get isAvailable;

  /// Obtiene configuración del servicio
  Map<String, dynamic> getConfig();
}

/// Interface abstracta para servicios de IA conversacional
abstract class ConversationalAIService {
  /// Envía un mensaje y obtiene respuesta
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? context,
  });

  /// Obtiene modelos disponibles
  Future<List<String>> getAvailableModels();

  /// Verifica si el servicio está disponible y configurado
  bool get isAvailable;

  /// Obtiene configuración del servicio
  Map<String, dynamic> getConfig();
}

/// Interface para servicios de llamadas de voz
abstract class VoiceCallService {
  /// Inicia una llamada de voz
  Future<bool> startCall({required Map<String, dynamic> config});

  /// Procesa audio de entrada del usuario
  Future<void> processUserAudio(Uint8List audioData);

  /// Procesa texto de entrada del usuario
  Future<void> processUserText(String text);

  /// Detiene la llamada
  Future<void> stopCall();

  /// Stream de texto generado por la IA
  Stream<String> get textStream;

  /// Stream de audio generado para reproducir
  Stream<Uint8List> get audioStream;

  /// Verifica si hay una llamada activa
  bool get isCallActive;

  /// Obtiene el historial de la conversación
  List<Map<String, String>> get conversationHistory;
}
