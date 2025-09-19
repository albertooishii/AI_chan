import 'package:ai_chan/shared.dart';

/// 🎯 DDD: Puerto para conversaciones de voz completas
/// Orquesta TTS, STT y respuestas de IA para crear un flujo conversacional
abstract interface class IVoiceConversationService {
  /// Iniciar una nueva conversación de voz
  Future<void> startConversation({
    final VoiceSettings? voiceSettings,
    final String? initialMessage,
  });

  /// Procesar entrada de voz del usuario
  Future<ConversationTurn> processVoiceInput({
    required final List<int> audioData,
    required final String format,
  });

  /// Procesar entrada de texto (para conversación mixta)
  Future<ConversationTurn> processTextInput({required final String text});

  /// Finalizar conversación
  Future<void> endConversation();

  /// Stream de turnos de conversación
  Stream<ConversationTurn> get conversationStream;

  /// Stream del estado de la conversación
  Stream<ConversationState> get stateStream;

  /// Estado actual de la conversación
  ConversationState get currentState;

  /// Verificar si hay una conversación activa
  bool get isConversationActive;

  /// Obtener historial de la conversación
  List<ConversationTurn> get conversationHistory;

  /// Configurar settings de voz
  void updateVoiceSettings(final VoiceSettings settings);
}

/// 🎯 DDD: Turno individual en la conversación
class ConversationTurn {
  // Confianza del STT (solo para turnos del usuario)

  /// Factory para turno del usuario
  factory ConversationTurn.user({
    required final String content,
    required final List<int> audioData,
    final double? confidence,
    final Duration? duration,
  }) {
    return ConversationTurn(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      speaker: ConversationSpeaker.user,
      content: content,
      timestamp: DateTime.now(),
      audioData: audioData,
      confidence: confidence,
      duration: duration,
    );
  }

  /// Factory para turno de la IA
  factory ConversationTurn.ai({
    required final String content,
    final List<int>? audioData,
    final Duration? duration,
  }) {
    return ConversationTurn(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      speaker: ConversationSpeaker.ai,
      content: content,
      timestamp: DateTime.now(),
      audioData: audioData,
      duration: duration,
    );
  }
  const ConversationTurn({
    required this.id,
    required this.speaker,
    required this.content,
    required this.timestamp,
    this.audioData,
    this.duration,
    this.confidence,
  });

  final String id;
  final ConversationSpeaker speaker;
  final String content;
  final DateTime timestamp;
  final List<int>?
  audioData; // Audio original (si es del usuario) o generado (si es de IA)
  final Duration? duration;
  final double? confidence;

  @override
  String toString() =>
      'ConversationTurn(${speaker.name}: "$content", ${timestamp.toIso8601String()})';
}

/// 🎯 DDD: Participantes en la conversación
enum ConversationSpeaker { user, ai }

extension ConversationSpeakerExtension on ConversationSpeaker {
  String get displayName {
    switch (this) {
      case ConversationSpeaker.user:
        return 'Usuario';
      case ConversationSpeaker.ai:
        return 'AI-Chan';
    }
  }

  String get emoji {
    switch (this) {
      case ConversationSpeaker.user:
        return '🗣️';
      case ConversationSpeaker.ai:
        return '🤖';
    }
  }
}

/// 🎯 DDD: Estados de la conversación
enum ConversationState { idle, listening, processing, speaking, error }

extension ConversationStateExtension on ConversationState {
  String get displayName {
    switch (this) {
      case ConversationState.idle:
        return 'Esperando';
      case ConversationState.listening:
        return 'Escuchando';
      case ConversationState.processing:
        return 'Procesando';
      case ConversationState.speaking:
        return 'Hablando';
      case ConversationState.error:
        return 'Error';
    }
  }

  String get emoji {
    switch (this) {
      case ConversationState.idle:
        return '💤';
      case ConversationState.listening:
        return '👂';
      case ConversationState.processing:
        return '🧠';
      case ConversationState.speaking:
        return '🗣️';
      case ConversationState.error:
        return '❌';
    }
  }

  bool get isActive =>
      this != ConversationState.idle && this != ConversationState.error;
}

/// 🎯 DDD: Configuración de conversación
class ConversationConfig {
  // Permitir interrumpir a la IA mientras habla

  /// Configuración para conversación casual
  factory ConversationConfig.casual() {
    return const ConversationConfig(
      maxTurns: 100,
      autoEndAfterSilence: Duration(minutes: 5),
      maxTurnDuration: Duration(seconds: 30),
    );
  }

  /// Configuración para entrevista/formal
  factory ConversationConfig.formal() {
    return const ConversationConfig(
      maxTurns: 20,
      autoEndAfterSilence: Duration(minutes: 1),
      maxTurnDuration: Duration(minutes: 2),
      enableContinuousListening: false,
      enableInterruption: false,
    );
  }
  const ConversationConfig({
    this.maxTurns = 50,
    this.autoEndAfterSilence = const Duration(minutes: 2),
    this.maxTurnDuration = const Duration(minutes: 1),
    this.enableContinuousListening = true,
    this.enableInterruption = true,
  });

  final int maxTurns;
  final Duration autoEndAfterSilence;
  final Duration maxTurnDuration;
  final bool enableContinuousListening;
  final bool enableInterruption;
}

/// 🎯 DDD: Excepciones de conversación
class VoiceConversationException implements Exception {
  const VoiceConversationException(this.message, {this.originalError});

  final String message;
  final Object? originalError;

  @override
  String toString() => 'VoiceConversationException: $message';
}
