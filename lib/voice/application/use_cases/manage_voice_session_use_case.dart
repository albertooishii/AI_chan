import '../../domain/entities/voice_session.dart';
import '../../../shared/ai_providers/core/models/audio/voice_settings.dart';
import '../../domain/interfaces/voice_services.dart';
import '../../domain/services/voice_session_orchestrator.dart';

// Re-exportar tipos del dominio para conveniencia
export '../../domain/entities/voice_session.dart';
export '../../../shared/ai_providers/core/models/audio/voice_settings.dart';
export '../../domain/interfaces/voice_services.dart';
export '../../domain/services/voice_session_orchestrator.dart';

/// 🎯 DDD: Caso de uso para gestionar sesiones de voz
/// Coordina entre dominio e infraestructura
class ManageVoiceSessionUseCase {
  const ManageVoiceSessionUseCase({
    required this.ttsService,
    required this.sttService,
  });

  final ITextToSpeechService ttsService;
  final ISpeechToTextService sttService;

  /// Crear nueva sesión de voz
  Future<VoiceSession> createSession({
    final String? sessionId,
    final VoiceSettings? settings,
    final Map<String, dynamic>? metadata,
  }) async {
    final id = sessionId ?? _generateSessionId();
    final voiceSettings = settings ?? VoiceSettings.defaultSettings();

    final orchestrator = VoiceSessionOrchestrator(
      ttsService: ttsService,
      sttService: sttService,
    );

    return orchestrator.createSession(
      sessionId: id,
      settings: voiceSettings,
      metadata: metadata,
    );
  }

  /// Procesar mensaje del usuario
  Future<VoiceSession> processUserMessage({
    required final VoiceSession session,
    required final String text,
    final List<int>? audioData,
  }) async {
    final messageId = _generateMessageId();

    final orchestrator = VoiceSessionOrchestrator(
      ttsService: ttsService,
      sttService: sttService,
    );

    return orchestrator.processUserMessage(
      session: session,
      messageId: messageId,
      userText: text,
      userAudio: audioData,
    );
  }

  /// Finalizar sesión
  VoiceSession endSession(final VoiceSession session) {
    return session.end();
  }

  /// Validar configuración de voz
  Future<VoiceValidationResult> validateSettings(final VoiceSettings settings) {
    final orchestrator = VoiceSessionOrchestrator(
      ttsService: ttsService,
      sttService: sttService,
    );
    return orchestrator.validateVoiceSettings(settings);
  }

  /// Obtener estadísticas
  VoiceSessionStats getStats(final VoiceSession session) {
    final orchestrator = VoiceSessionOrchestrator(
      ttsService: ttsService,
      sttService: sttService,
    );
    return orchestrator.getSessionStats(session);
  }

  /// Obtener voces disponibles
  Future<List<VoiceInfo>> getAvailableVoices({
    final String language = 'es-ES',
  }) {
    return ttsService.getAvailableVoices(language: language);
  }

  /// Obtener idiomas soportados
  Future<List<String>> getSupportedLanguages() {
    return ttsService.getSupportedLanguages();
  }

  /// Previsualizar voz
  Future<SynthesisResult> previewVoice({
    required final String voiceId,
    required final String language,
    final String sampleText = 'Hola, esta es una prueba de voz.',
  }) {
    return ttsService.previewVoice(
      voiceId: voiceId,
      language: language,
      sampleText: sampleText,
    );
  }

  // Generadores de ID
  String _generateSessionId() {
    return 'voice_session_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateMessageId() {
    return 'voice_msg_${DateTime.now().millisecondsSinceEpoch}';
  }
}
