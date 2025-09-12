import 'dart:async';
import '../../domain/interfaces/i_voice_conversation_service.dart';
import '../../../shared/ai_providers/core/interfaces/audio/i_audio_recorder_service.dart';
import '../../../shared/ai_providers/core/interfaces/audio/i_tts_service.dart';
import '../../../shared/ai_providers/core/interfaces/audio/i_stt_service.dart';
import '../../../shared/ai_providers/core/models/audio/voice_settings.dart';
import '../../../shared/ai_providers/core/services/audio/centralized_audio_playback_service.dart';
import '../../../shared/ai_providers/core/interfaces/audio/i_audio_playback_service.dart';
import '../../../shared/ai_providers/core/models/audio/audio_playback_config.dart';
import '../../../shared/ai_providers/core/services/ai_provider_manager.dart';
import '../../../shared/ai_providers/core/models/ai_capability.dart';
import '../../../core/models/system_prompt.dart';
import '../../../core/models/ai_chan_profile.dart';
import '../../../shared/utils/log_utils.dart';
import '../../../shared/ai_providers/core/services/audio/centralized_audio_recorder_service.dart';
import '../../../shared/ai_providers/core/services/audio/centralized_tts_service.dart';
import '../../../shared/ai_providers/core/services/audio/centralized_stt_service.dart';

/// 🎯 DDD: Orquestador de conversaciones de voz completas
/// Integra TTS, STT, audio player/recorder y respuestas de IA
class VoiceConversationService implements IVoiceConversationService {
  VoiceConversationService._();

  static final VoiceConversationService _instance =
      VoiceConversationService._();
  static VoiceConversationService get instance => _instance;

  // Servicios de dominio
  final ITtsService _ttsService = CentralizedTtsService.instance;
  final ISttService _sttService = CentralizedSttService.instance;
  final IAudioPlaybackService _audioPlayer =
      CentralizedAudioPlaybackService.instance;
  final IAudioRecorderService _audioRecorder =
      CentralizedAudioRecorderService.instance;
  final AIProviderManager _aiProviderManager = AIProviderManager.instance;

  // Estado de la conversación
  final StreamController<ConversationTurn> _conversationController =
      StreamController<ConversationTurn>.broadcast();
  final StreamController<ConversationState> _stateController =
      StreamController<ConversationState>.broadcast();

  ConversationState _currentState = ConversationState.idle;
  final List<ConversationTurn> _conversationHistory = [];
  VoiceSettings? _voiceSettings; // Nullable para lazy initialization
  bool _isConversationActive = false;

  /// Getter que inicializa configuraciones de voz bajo demanda
  Future<VoiceSettings> get voiceSettings async {
    if (_voiceSettings != null) {
      return _voiceSettings!;
    }

    await _initializeVoiceSettings();
    return _voiceSettings!;
  }

  /// Inicializa las configuraciones de voz o lanza error explicativo
  Future<void> _initializeVoiceSettings() async {
    try {
      // Obtener el primer provider disponible con capacidad de audio dinámicamente
      final audioProvider = await _aiProviderManager.getProviderForCapability(
        AICapability.audioGeneration,
      );

      if (audioProvider == null) {
        throw StateError(
          'VoiceConversationService: No hay providers de audio disponibles. '
          'Configure al menos un provider con capacidad audioGeneration en ai_providers_config.yaml',
        );
      }

      // Intentar obtener voz por defecto del provider dinámicamente
      String? defaultVoice;
      try {
        final concreteProvider = audioProvider as dynamic;
        if (concreteProvider.runtimeType.toString().contains(
          'getDefaultVoice',
        )) {
          defaultVoice = concreteProvider.getDefaultVoice() as String?;
        }
      } on Exception catch (e) {
        Log.w(
          '[VoiceConversation] Provider ${audioProvider.providerId} no expone getDefaultVoice(): $e',
        );
      }

      if (defaultVoice == null || defaultVoice.isEmpty) {
        throw StateError(
          'VoiceConversationService: El provider ${audioProvider.providerId} no tiene voz por defecto configurada. '
          'Configure voces por defecto en ai_providers_config.yaml o seleccione en configuración TTS.',
        );
      }

      _voiceSettings = VoiceSettings.create(
        voiceId: defaultVoice,
        language: 'es-ES', // Esto también debería venir de configuración
      );

      Log.d(
        '[VoiceConversation] ✅ Voz inicializada: $defaultVoice del provider ${audioProvider.providerId}',
      );
    } on Exception catch (e) {
      throw StateError(
        'VoiceConversationService: No se pudo inicializar configuración de voz. '
        'Error: $e',
      );
    }
  }

  @override
  Stream<ConversationTurn> get conversationStream =>
      _conversationController.stream;

  @override
  Stream<ConversationState> get stateStream => _stateController.stream;

  @override
  ConversationState get currentState => _currentState;

  @override
  bool get isConversationActive => _isConversationActive;

  @override
  List<ConversationTurn> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  @override
  Future<void> startConversation({
    final VoiceSettings? voiceSettings,
    final String? initialMessage,
  }) async {
    try {
      if (_isConversationActive) {
        throw const VoiceConversationException(
          'Ya hay una conversación activa',
        );
      }

      Log.d('[VoiceConversation] 🎯 Iniciando conversación de voz');

      // Configurar settings
      if (voiceSettings != null) {
        _voiceSettings = voiceSettings;
      }

      // Verificar permisos de audio
      if (!await _audioRecorder.hasPermissions()) {
        final granted = await _audioRecorder.requestPermissions();
        if (!granted) {
          throw const VoiceConversationException(
            'Permisos de micrófono requeridos',
          );
        }
      }

      _isConversationActive = true;
      _conversationHistory.clear();
      _updateState(ConversationState.idle);

      // Mensaje inicial de la IA si se proporciona
      if (initialMessage != null && initialMessage.isNotEmpty) {
        await _speakMessage(initialMessage);
      } else {
        // Saludo por defecto
        await _speakMessage('¡Hola! Soy AI-Chan. ¿En qué puedo ayudarte?');
      }

      Log.d('[VoiceConversation] ✅ Conversación iniciada');
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error iniciando conversación: $e');
      _updateState(ConversationState.error);
      rethrow;
    }
  }

  @override
  Future<ConversationTurn> processVoiceInput({
    required final List<int> audioData,
    required final String format,
  }) async {
    try {
      if (!_isConversationActive) {
        throw const VoiceConversationException('No hay conversación activa');
      }

      _updateState(ConversationState.processing);

      Log.d(
        '[VoiceConversation] 🎤 Procesando entrada de voz: ${audioData.length} bytes',
      );

      // 1. Transcribir audio con STT
      final settings = await voiceSettings;
      final recognitionResult = await _sttService.recognizeAudio(
        audioData: audioData,
        language: settings.language,
        format: format,
      );

      if (recognitionResult.text.trim().isEmpty) {
        throw const VoiceConversationException(
          'No se pudo transcribir el audio',
        );
      }

      // 2. Crear turno del usuario
      final userTurn = ConversationTurn.user(
        content: recognitionResult.text,
        audioData: audioData,
        confidence: recognitionResult.confidence,
        duration: recognitionResult.duration,
      );

      _conversationHistory.add(userTurn);
      _conversationController.add(userTurn);

      Log.d('[VoiceConversation] 👤 Usuario: "${recognitionResult.text}"');

      // 3. Generar respuesta de IA
      final aiResponse = await _generateAIResponse(recognitionResult.text);

      // 4. Crear turno de IA y hablar
      await _speakMessage(aiResponse);

      return userTurn;
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error procesando entrada de voz: $e');
      _updateState(ConversationState.error);
      rethrow;
    }
  }

  @override
  Future<ConversationTurn> processTextInput({
    required final String text,
  }) async {
    try {
      if (!_isConversationActive) {
        throw const VoiceConversationException('No hay conversación activa');
      }

      _updateState(ConversationState.processing);

      Log.d('[VoiceConversation] 💬 Procesando entrada de texto: "$text"');

      // 1. Crear turno del usuario (sin audio)
      final userTurn = ConversationTurn.user(
        content: text,
        audioData: [],
        confidence: 1.0, // Texto tiene confianza máxima
      );

      _conversationHistory.add(userTurn);
      _conversationController.add(userTurn);

      // 2. Generar respuesta de IA
      final aiResponse = await _generateAIResponse(text);

      // 3. Crear turno de IA y hablar
      await _speakMessage(aiResponse);

      return userTurn;
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error procesando entrada de texto: $e');
      _updateState(ConversationState.error);
      rethrow;
    }
  }

  @override
  Future<void> endConversation() async {
    try {
      Log.d('[VoiceConversation] 🏁 Finalizando conversación');

      // Detener cualquier reproducción/grabación activa
      await _audioPlayer.stop();
      await _audioRecorder.cancelRecording();

      _isConversationActive = false;
      _updateState(ConversationState.idle);

      // Mensaje de despedida
      await _speakMessage('¡Hasta luego! Ha sido un placer hablar contigo.');

      Log.d('[VoiceConversation] ✅ Conversación finalizada');
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error finalizando conversación: $e');
    }
  }

  @override
  void updateVoiceSettings(final VoiceSettings settings) {
    _voiceSettings = settings;
    Log.d('[VoiceConversation] 🎛️ Settings actualizados: ${settings.voiceId}');
  }

  /// Generar respuesta de IA usando el chat system
  Future<String> _generateAIResponse(final String userMessage) async {
    try {
      // Crear SystemPrompt usando el constructor correcto
      final systemPrompt = SystemPrompt(
        profile: AiChanProfile(
          userName: 'Usuario',
          aiName: 'AI-Chan',
          userBirthdate: null,
          aiBirthdate: null,
          biography: const {},
          appearance: const {},
          userCountryCode: 'ES',
          aiCountryCode: 'JP',
          avatars: const [],
        ),
        dateTime: DateTime.now(),
        instructions: {
          'role': 'Eres AI-Chan, una asistente virtual amigable y útil.',
          'style': 'Responde de manera conversacional, natural y concisa.',
          'tone': 'Mantén un tono cálido y profesional.',
        },
      );

      // Usar AIProviderManager directamente para conversación
      final conversationHistory = _buildConversationHistory(userMessage);

      final aiResponse = await _aiProviderManager.sendMessage(
        history: conversationHistory,
        systemPrompt: systemPrompt,
        additionalParams: {'max_tokens': 150, 'temperature': 0.7, 'top_p': 0.9},
      );

      return aiResponse.text.trim();
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error generando respuesta de IA: $e');
      return 'Disculpa, tuve un problema procesando tu mensaje. ¿Podrías repetirlo?';
    }
  }

  /// Construir historial de conversación para la IA
  List<Map<String, String>> _buildConversationHistory(
    final String currentMessage,
  ) {
    final history = <Map<String, String>>[];

    // Incluir últimos 10 turnos para contexto
    final recentTurns = _conversationHistory.length > 10
        ? _conversationHistory.sublist(_conversationHistory.length - 10)
        : _conversationHistory;

    for (final turn in recentTurns) {
      final role = turn.speaker == ConversationSpeaker.user
          ? 'user'
          : 'assistant';
      history.add({'role': role, 'content': turn.content});
    }

    // Agregar mensaje actual del usuario
    history.add({'role': 'user', 'content': currentMessage});

    return history;
  }

  /// Sintetizar y reproducir mensaje de IA
  Future<ConversationTurn> _speakMessage(final String message) async {
    try {
      _updateState(ConversationState.speaking);

      Log.d('[VoiceConversation] 🤖 AI-Chan: "$message"');

      // 1. Sintetizar con TTS
      final settings = await voiceSettings;
      final synthesisResult = await _ttsService.synthesize(
        text: message,
        settings: settings,
      );

      // 2. Reproducir audio
      await _audioPlayer.playAudioBytes(
        audioData: synthesisResult.audioData,
        format: synthesisResult.format,
        config: AudioPlaybackConfig(volume: settings.volume),
      );

      // 3. Crear turno de IA
      final aiTurn = ConversationTurn.ai(
        content: message,
        audioData: synthesisResult.audioData,
        duration: synthesisResult.duration,
      );

      _conversationHistory.add(aiTurn);
      _conversationController.add(aiTurn);

      // 4. Volver a estado de escucha
      _updateState(ConversationState.listening);

      return aiTurn;
    } on Exception catch (e) {
      Log.e('[VoiceConversation] ❌ Error sintetizando mensaje: $e');
      _updateState(ConversationState.error);
      rethrow;
    }
  }

  /// Actualizar estado y notificar
  void _updateState(final ConversationState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
      Log.d(
        '[VoiceConversation] Estado: ${newState.displayName} ${newState.emoji}',
      );
    }
  }

  /// Limpiar recursos
  void dispose() {
    endConversation();
    _conversationController.close();
    _stateController.close();
  }
}
