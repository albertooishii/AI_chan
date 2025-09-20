import 'package:ai_chan/voice/domain/entities/voice_session.dart';
import 'package:ai_chan/shared.dart';

/// 🎯 DDD: Servicio de dominio para orquestación de sesiones de voz
/// Contiene lógica de negocio que no pertenece a una entidad específica
class VoiceSessionOrchestrator {
  const VoiceSessionOrchestrator({
    required this.ttsService,
    required this.sttService,
  });

  final CentralizedTtsService ttsService;
  final CentralizedSttService sttService;

  /// Crear nueva sesión de voz
  Future<VoiceSession> createSession({
    required final String sessionId,
    required final VoiceSettings settings,
    final Map<String, dynamic>? metadata,
  }) async {
    // Validar que los servicios estén disponibles
    final ttsAvailable = await ttsService.isAvailable();
    final sttAvailable = await sttService.isAvailable();

    if (!ttsAvailable && !sttAvailable) {
      throw const VoiceSessionException('No hay servicios de voz disponibles');
    }

    // Validar que el idioma esté soportado
    final ttsLanguages = await ttsService.getSupportedLanguages();
    final sttLanguages = await sttService.getSupportedLanguages();

    if (!ttsLanguages.contains(settings.language) &&
        !sttLanguages.contains(settings.language)) {
      throw VoiceSessionException('Idioma ${settings.language} no soportado');
    }

    return VoiceSession.start(
      id: sessionId,
      settings: settings,
      metadata: {
        ...metadata ?? {},
        'ttsAvailable': ttsAvailable,
        'sttAvailable': sttAvailable,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Procesar mensaje del usuario (STT + response + TTS)
  Future<VoiceSession> processUserMessage({
    required final VoiceSession session,
    required final String messageId,
    required final String userText,
    final List<int>? userAudio,
  }) async {
    // Agregar mensaje del usuario
    final userMessage = VoiceMessage.fromUser(
      id: messageId,
      text: userText,
      audioData: userAudio,
    );

    final updatedSession = session.addMessage(userMessage);

    // Aquí iría la lógica de generar respuesta del AI
    // Por ahora simulamos una respuesta simple
    final aiResponse = await _generateAIResponse(userText);
    final aiMessageId = '${messageId}_ai';

    // Sintetizar respuesta a audio
    SynthesisResult? synthesis;
    if (await ttsService.isAvailable()) {
      try {
        synthesis = await ttsService.synthesize(
          text: aiResponse,
          settings: session.settings,
        );
      } on Exception {
        // Error en TTS - continuar sin audio
        // Nota: En domain no usamos logging específico de framework
      }
    }

    // Agregar mensaje del AI
    final aiMessage = VoiceMessage.fromAssistant(
      id: aiMessageId,
      text: aiResponse,
      audioData: synthesis?.audioData,
      duration: synthesis?.duration,
    );

    return updatedSession.addMessage(aiMessage);
  }

  /// Validar configuración de voz
  Future<VoiceValidationResult> validateVoiceSettings(
    final VoiceSettings settings,
  ) async {
    final issues = <String>[];

    // Verificar idioma
    final ttsLanguages = await ttsService.getSupportedLanguages();
    final sttLanguages = await sttService.getSupportedLanguages();

    if (!ttsLanguages.contains(settings.language)) {
      issues.add('Idioma ${settings.language} no soportado por TTS');
    }

    if (!sttLanguages.contains(settings.language)) {
      issues.add('Idioma ${settings.language} no soportado por STT');
    }

    // Verificar voz disponible
    try {
      final voices = await ttsService.getAvailableVoices(
        language: settings.language,
      );
      if (!voices.any((final v) => v.id == settings.voiceId)) {
        issues.add(
          'Voz ${settings.voiceId} no disponible para ${settings.language}',
        );
      }
    } on Exception catch (e) {
      issues.add('Error al verificar voces disponibles: $e');
    }

    return VoiceValidationResult(isValid: issues.isEmpty, issues: issues);
  }

  /// Obtener estadísticas de sesión
  VoiceSessionStats getSessionStats(final VoiceSession session) {
    final userMessages = session.messages.where((final m) => m.isUser).length;
    final aiMessages = session.messages
        .where((final m) => m.isAssistant)
        .length;
    final messagesWithAudio = session.messages
        .where((final m) => m.hasAudio)
        .length;

    return VoiceSessionStats(
      totalMessages: session.messageCount,
      userMessages: userMessages,
      aiMessages: aiMessages,
      messagesWithAudio: messagesWithAudio,
      duration: session.duration,
      averageMessageLength: session.messages.isEmpty
          ? 0
          : session.messages
                    .map((final m) => m.text.length)
                    .reduce((final a, final b) => a + b) /
                session.messageCount,
    );
  }

  // Simulación de respuesta AI - en implementación real iría a AIProviderManager
  Future<String> _generateAIResponse(final String userInput) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simular latencia
    return 'Entiendo que dices "$userInput". ¿En qué más puedo ayudarte?';
  }
}

/// 🎯 DDD: Resultado de validación
class VoiceValidationResult {
  const VoiceValidationResult({required this.isValid, required this.issues});

  final bool isValid;
  final List<String> issues;

  @override
  String toString() =>
      'VoiceValidation(valid: $isValid, issues: ${issues.length})';
}

/// 🎯 DDD: Estadísticas de sesión
class VoiceSessionStats {
  const VoiceSessionStats({
    required this.totalMessages,
    required this.userMessages,
    required this.aiMessages,
    required this.messagesWithAudio,
    required this.duration,
    required this.averageMessageLength,
  });

  final int totalMessages;
  final int userMessages;
  final int aiMessages;
  final int messagesWithAudio;
  final Duration duration;
  final double averageMessageLength;

  @override
  String toString() =>
      'VoiceStats($totalMessages msgs, ${duration.inSeconds}s)';
}

/// 🎯 DDD: Excepción del dominio
class VoiceSessionException implements Exception {
  const VoiceSessionException(this.message);
  final String message;

  @override
  String toString() => 'VoiceSessionException: $message';
}
