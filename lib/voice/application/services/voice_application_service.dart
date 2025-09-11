import '../use_cases/manage_voice_session_use_case.dart';

/// 🎯 DDD: Servicio de aplicación para gestión completa de voz
/// Coordina múltiples casos de uso y maneja flujos complejos
class VoiceApplicationService {
  VoiceApplicationService({required this.useCase});

  final ManageVoiceSessionUseCase useCase;
  final Map<String, VoiceSession> _activeSessions = {};

  /// 🚀 Flujo completo: Crear y inicializar sesión
  Future<VoiceSessionState> startVoiceSession({
    final String? sessionId,
    final VoiceSettings? settings,
    final Map<String, dynamic>? metadata,
  }) async {
    try {
      // Crear sesión
      final session = await useCase.createSession(
        sessionId: sessionId,
        settings: settings,
        metadata: metadata,
      );

      // Registrar sesión activa
      _activeSessions[session.id] = session;

      // Validar configuración
      final validation = await useCase.validateSettings(session.settings);

      return VoiceSessionState(
        session: session,
        isActive: true,
        validation: validation,
        stats: useCase.getStats(session),
      );
    } on Exception catch (e) {
      return VoiceSessionState.error(
        error: 'Error iniciando sesión de voz: $e',
      );
    }
  }

  /// 🗣️ Flujo completo: Procesar entrada del usuario
  Future<VoiceInteractionResult> processUserInput({
    required final String sessionId,
    final String? text,
    final List<int>? audioData,
  }) async {
    try {
      final session = _activeSessions[sessionId];
      if (session == null) {
        return VoiceInteractionResult.error(
          error: 'Sesión no encontrada: $sessionId',
        );
      }

      // Determinar tipo de entrada
      String processedText = text ?? '';

      // Si hay audio, reconocerlo primero
      if (audioData != null && audioData.isNotEmpty) {
        // TODO: Implementar reconocimiento cuando esté disponible
        processedText = '[Audio reconocido]';
      }

      if (processedText.isEmpty) {
        return const VoiceInteractionResult.error(
          error: 'No hay texto ni audio para procesar',
        );
      }

      // Procesar mensaje
      final updatedSession = await useCase.processUserMessage(
        session: session,
        text: processedText,
        audioData: audioData,
      );

      // Actualizar sesión activa
      _activeSessions[sessionId] = updatedSession;

      return VoiceInteractionResult(
        session: updatedSession,
        processedText: processedText,
        hasAudio: audioData != null,
        stats: useCase.getStats(updatedSession),
      );
    } on Exception catch (e) {
      return VoiceInteractionResult.error(
        error: 'Error procesando entrada: $e',
      );
    }
  }

  /// 🔊 Flujo completo: Generar respuesta de voz
  Future<VoiceResponseResult> generateVoiceResponse({
    required final String sessionId,
    required final String responseText,
  }) async {
    try {
      final session = _activeSessions[sessionId];
      if (session == null) {
        return VoiceResponseResult.error(
          error: 'Sesión no encontrada: $sessionId',
        );
      }

      // TODO: Sintetizar cuando esté disponible
      // final synthesis = await _ttsService.synthesize(
      //   text: responseText,
      //   settings: session.settings,
      // );

      // Por ahora simular
      final simulatedAudio = List.generate(1000, (final i) => (i % 256));

      return VoiceResponseResult(
        session: session,
        responseText: responseText,
        audioData: simulatedAudio,
        duration: Duration(milliseconds: responseText.length * 50),
        format: 'wav',
      );
    } on Exception catch (e) {
      return VoiceResponseResult.error(error: 'Error generando respuesta: $e');
    }
  }

  /// ⚙️ Configurar voz en sesión activa
  Future<VoiceConfigurationResult> configureVoice({
    required final String sessionId,
    required final VoiceSettings newSettings,
  }) async {
    try {
      final session = _activeSessions[sessionId];
      if (session == null) {
        return VoiceConfigurationResult.error(
          error: 'Sesión no encontrada: $sessionId',
        );
      }

      // Validar nueva configuración
      final validation = await useCase.validateSettings(newSettings);
      if (!validation.isValid) {
        return VoiceConfigurationResult.error(
          error: 'Configuración inválida: ${validation.issues.join(', ')}',
        );
      }

      // Actualizar configuración
      final updatedSession = session.updateSettings(newSettings);
      _activeSessions[sessionId] = updatedSession;

      return VoiceConfigurationResult(
        session: updatedSession,
        validation: validation,
        availableVoices: await useCase.getAvailableVoices(
          language: newSettings.language,
        ),
      );
    } on Exception catch (e) {
      return VoiceConfigurationResult.error(
        error: 'Error configurando voz: $e',
      );
    }
  }

  /// 🏁 Finalizar sesión de voz
  VoiceSessionState endVoiceSession(final String sessionId) {
    try {
      final session = _activeSessions[sessionId];
      if (session == null) {
        return VoiceSessionState.error(
          error: 'Sesión no encontrada: $sessionId',
        );
      }

      final endedSession = useCase.endSession(session);
      _activeSessions.remove(sessionId);

      return VoiceSessionState(
        session: endedSession,
        isActive: false,
        stats: useCase.getStats(endedSession),
      );
    } on Exception catch (e) {
      return VoiceSessionState.error(error: 'Error finalizando sesión: $e');
    }
  }

  /// 📊 Obtener estado de todas las sesiones
  Map<String, VoiceSessionState> getAllSessionStates() {
    return _activeSessions.map(
      (final id, final session) => MapEntry(
        id,
        VoiceSessionState(
          session: session,
          isActive: true,
          stats: useCase.getStats(session),
        ),
      ),
    );
  }

  /// 🔍 Buscar sesión activa
  VoiceSession? getActiveSession(final String sessionId) {
    return _activeSessions[sessionId];
  }

  /// 🎛️ Obtener capacidades de voz
  Future<VoiceCapabilities> getVoiceCapabilities({
    final String language = 'es-ES',
  }) async {
    try {
      final voices = await useCase.getAvailableVoices(language: language);
      final languages = await useCase.getSupportedLanguages();

      return VoiceCapabilities(
        availableVoices: voices,
        supportedLanguages: languages,
        hasTextToSpeech: true,
        hasSpeechToText: true,
        supportsRealTimeSTT: true,
        supportsVoicePreview: true,
      );
    } on Exception {
      return const VoiceCapabilities.empty();
    }
  }
}

/// 🎯 Estados y resultados del servicio de aplicación

class VoiceSessionState {
  const VoiceSessionState({
    required this.session,
    required this.isActive,
    this.validation,
    this.stats,
    this.error,
  });

  const VoiceSessionState.error({required this.error})
    : session = null,
      isActive = false,
      validation = null,
      stats = null;

  final VoiceSession? session;
  final bool isActive;
  final VoiceValidationResult? validation;
  final VoiceSessionStats? stats;
  final String? error;

  bool get hasError => error != null;
  bool get isValid => !hasError && session != null;
}

class VoiceInteractionResult {
  const VoiceInteractionResult({
    required this.session,
    required this.processedText,
    required this.hasAudio,
    this.stats,
    this.error,
  });

  const VoiceInteractionResult.error({required this.error})
    : session = null,
      processedText = '',
      hasAudio = false,
      stats = null;

  final VoiceSession? session;
  final String processedText;
  final bool hasAudio;
  final VoiceSessionStats? stats;
  final String? error;

  bool get hasError => error != null;
  bool get isValid => !hasError && session != null;
}

class VoiceResponseResult {
  const VoiceResponseResult({
    required this.session,
    required this.responseText,
    required this.audioData,
    required this.duration,
    required this.format,
    this.error,
  });

  const VoiceResponseResult.error({required this.error})
    : session = null,
      responseText = '',
      audioData = const [],
      duration = Duration.zero,
      format = '';

  final VoiceSession? session;
  final String responseText;
  final List<int> audioData;
  final Duration duration;
  final String format;
  final String? error;

  bool get hasError => error != null;
  bool get isValid => !hasError && session != null;
}

class VoiceConfigurationResult {
  const VoiceConfigurationResult({
    required this.session,
    required this.validation,
    required this.availableVoices,
    this.error,
  });

  const VoiceConfigurationResult.error({required this.error})
    : session = null,
      validation = null,
      availableVoices = const [];

  final VoiceSession? session;
  final VoiceValidationResult? validation;
  final List<VoiceInfo> availableVoices;
  final String? error;

  bool get hasError => error != null;
  bool get isValid => !hasError && session != null;
}

class VoiceCapabilities {
  const VoiceCapabilities({
    required this.availableVoices,
    required this.supportedLanguages,
    required this.hasTextToSpeech,
    required this.hasSpeechToText,
    required this.supportsRealTimeSTT,
    required this.supportsVoicePreview,
  });

  const VoiceCapabilities.empty()
    : availableVoices = const [],
      supportedLanguages = const [],
      hasTextToSpeech = false,
      hasSpeechToText = false,
      supportsRealTimeSTT = false,
      supportsVoicePreview = false;

  final List<VoiceInfo> availableVoices;
  final List<String> supportedLanguages;
  final bool hasTextToSpeech;
  final bool hasSpeechToText;
  final bool supportsRealTimeSTT;
  final bool supportsVoicePreview;

  bool get isFullySupported => hasTextToSpeech && hasSpeechToText;
}
