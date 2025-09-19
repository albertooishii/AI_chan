// Shared Domain Interfaces for Cross-Context Communication
//
// This file contains interfaces that allow bounded contexts to communicate
// without creating direct dependencies between them.

import 'package:ai_chan/shared.dart';

/// Interface for chat integration services
/// Allows call context to communicate with chat without direct dependency
abstract class IChatIntegrationService {
  /// Send a message from call context to chat
  Future<void> sendMessageFromCall(
    final String message,
    final Map<String, dynamic>? metadata,
  );

  /// Get chat status for call integration
  Future<bool> isChatAvailable();

  /// Notify chat about call events
  Future<void> notifyCallEvent(
    final String eventType,
    final Map<String, dynamic> data,
  );
}

/// Interface for call integration services
/// Allows chat context to communicate with call without direct dependency
abstract class ICallIntegrationService {
  /// Start a call from chat context
  Future<void> startCallFromChat();

  /// End current call
  Future<void> endCallFromChat();

  /// Check if call is active
  Future<bool> isCallActive();

  /// Send message to call context
  Future<void> sendMessageToCall(final String message);
}

/// 🎯 DDD: Puerto para síntesis de voz (TTS)
/// El dominio define QUÉ necesita, la infraestructura CÓMO lo hace
abstract interface class ITextToSpeechService {
  /// Sintetizar texto a audio
  Future<SynthesisResult> synthesize({
    required final String text,
    required final VoiceSettings settings,
  });

  /// Obtener voces disponibles para un idioma
  Future<List<VoiceInfo>> getAvailableVoices({required final String language});

  /// Verificar si el servicio está disponible
  Future<bool> isAvailable();

  /// Obtener idiomas soportados
  Future<List<String>> getSupportedLanguages();

  /// Previsualizar voz (para configuración)
  Future<SynthesisResult> previewVoice({
    required final String voiceId,
    required final String language,
    final String sampleText = 'Hola, esta es una prueba de voz.',
  });

  /// Legacy interface methods for backward compatibility
  Future<void> speak(
    final String text, {
    final String? language,
    final double? rate,
    final double? pitch,
  });
  Future<void> stop();
  Future<bool> isSpeaking();
}

/// 🎯 DDD: Puerto para reconocimiento de voz (STT)
abstract interface class ISpeechToTextService {
  /// Iniciar escucha en tiempo real
  Stream<RecognitionResult> startListening({
    required final String language,
    final bool enablePartialResults = true,
  });

  /// Detener escucha
  Future<void> stopListening();

  /// Reconocer audio desde datos
  Future<RecognitionResult> recognizeAudio({
    required final List<int> audioData,
    required final String language,
    final String format = 'wav',
  });

  /// Verificar disponibilidad
  Future<bool> isAvailable();

  /// Idiomas soportados
  Future<List<String>> getSupportedLanguages();

  /// ¿Está escuchando actualmente?
  bool get isListening;

  /// Legacy interface methods for backward compatibility
  Future<void> startListeningLegacy({final String? language});
  Future<void> stopListeningLegacy();
  Stream<String> get onTextReceived;
}

/// 🎯 DDD: Resultado de reconocimiento
class RecognitionResult {
  const RecognitionResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    required this.duration,
  });

  final String text;
  final double confidence;
  final bool isFinal;
  final Duration duration;

  @override
  String toString() =>
      'RecognitionResult("$text", confidence: $confidence, final: $isFinal)';
}

/// Shared DTOs for cross-context communication
class CallToChatMessage {
  CallToChatMessage({
    required this.content,
    required this.timestamp,
    this.metadata,
  });
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
}

class ChatToCallMessage {
  ChatToCallMessage({
    required this.content,
    required this.timestamp,
    required this.messageType,
  });
  final String content;
  final DateTime timestamp;
  final String messageType;

  Map<String, dynamic> toJson() => {
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'messageType': messageType,
  };
}
