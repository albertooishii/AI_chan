import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_chan/onboarding/domain/entities/onboarding_step.dart';
import 'package:ai_chan/onboarding/domain/entities/onboarding_state.dart';
import 'package:ai_chan/onboarding/application/use_cases/conversational_onboarding_use_case.dart';
import 'package:ai_chan/onboarding/application/services/voice_configuration_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/shared/services/hybrid_stt_service.dart';
import 'package:ai_chan/shared/widgets/conversational_subtitles.dart';
import 'package:ai_chan/shared/utils/audio_duration_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/onboarding/services/conversational_ai_service.dart';
import 'package:audioplayers/audioplayers.dart';

/// Controlador que maneja la lógica de presentación del onboarding conversacional
/// Separa la lógica de negocio de la UI
class ConversationalOnboardingController extends ChangeNotifier {
  // Use Cases y Services
  final ConversationalOnboardingUseCase _useCase;
  final VoiceConfigurationService _voiceConfigService;
  final ITtsService _ttsService;
  final HybridSttService _hybridSttService;
  final AudioPlayer _audioPlayer;
  final ConversationalSubtitleController _subtitleController;

  // Estado interno
  OnboardingState _state = const OnboardingState(
    currentStep: OnboardingStep.awakening,
    collectedData: {},
  );

  // Estado de UI
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isThinking = false;
  Timer? _speechTimeoutTimer;
  int _ttsRetryCount = 0;
  static const int _maxTtsRetries = 3;

  ConversationalOnboardingController({
    required ITtsService ttsService,
    required HybridSttService hybridSttService,
    required AudioPlayer audioPlayer,
    required ConversationalSubtitleController subtitleController,
    ConversationalOnboardingUseCase? useCase,
    VoiceConfigurationService? voiceConfigService,
  }) : _ttsService = ttsService,
       _hybridSttService = hybridSttService,
       _audioPlayer = audioPlayer,
       _subtitleController = subtitleController,
       _useCase = useCase ?? ConversationalOnboardingUseCase(),
       _voiceConfigService = voiceConfigService ?? VoiceConfigurationService();

  // Getters para la UI
  OnboardingState get state => _state;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isThinking => _isThinking;
  bool get isComplete => _useCase.isComplete(_state);
  bool get hasRequiredData => _useCase.hasRequiredData(_state);

  /// Inicia el flujo de onboarding
  Future<void> startOnboarding() async {
    Log.d('🚀 Iniciando onboarding conversacional', tag: 'CONV_CONTROLLER');
    await Future.delayed(const Duration(milliseconds: 1500));

    final initialMessage = _useCase.getInitialMessage(_state.currentStep);
    await _speakAndWaitForResponse(initialMessage);
  }

  /// Procesa una respuesta del usuario (voz o texto)
  Future<void> processUserResponse(
    String userResponse, {
    bool fromTextInput = false,
  }) async {
    if (userResponse.trim().isEmpty) {
      await _retryCurrentStep();
      return;
    }

    Log.d('🎤 Procesando respuesta: "$userResponse"', tag: 'CONV_CONTROLLER');

    _updateUIState(isListening: false, isThinking: true);
    _subtitleController.handleUserTranscription(userResponse);

    try {
      final newState = await _useCase.processUserResponse(
        userResponse: userResponse,
        currentState: _state,
      );

      // Verificar si la operación fue cancelada por una nueva
      if (newState.operationId != _state.operationId + 1) {
        Log.d(
          '🔄 Operación cancelada, ignorando resultado',
          tag: 'CONV_CONTROLLER',
        );
        _updateUIState(isThinking: false);
        return;
      }

      _updateState(newState);
      await _handleStateTransition();
    } catch (e) {
      Log.e('Error procesando respuesta: $e', tag: 'CONV_CONTROLLER');
      _updateUIState(isThinking: false);
      await _retryCurrentStep();
    }
  }

  /// Reinicia el paso actual por timeout o error
  Future<void> retryCurrentStep() async {
    await _retryCurrentStep();
  }

  /// Genera y reproduce el siguiente mensaje de la IA
  Future<void> generateNextAIMessage() async {
    if (_state.currentStep == OnboardingStep.completion) {
      Log.d('✅ Onboarding completado', tag: 'CONV_CONTROLLER');
      return;
    }

    try {
      _updateUIState(isThinking: true);

      final message = await ConversationalAIService.generateNextResponse(
        userName: _state.userName ?? '',
        userLastResponse: '',
        conversationStep: _state.currentStep.stepName,
        aiName: _state.aiName,
        aiCountryCode: _state.aiCountry,
        collectedData: _state.collectedData,
      );
      if (message.isNotEmpty) {
        await _speakAndWaitForResponse(message);
      } else {
        Log.w(
          'Mensaje vacío generado por IA, reintentando...',
          tag: 'CONV_CONTROLLER',
        );
        await _retryCurrentStep();
      }
    } catch (e) {
      Log.e('Error generando mensaje de IA: $e', tag: 'CONV_CONTROLLER');
      await _retryCurrentStep();
    }
  }

  @override
  void dispose() {
    _speechTimeoutTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Métodos privados ---

  void _updateState(OnboardingState newState) {
    _state = newState;
    notifyListeners();
  }

  void _updateUIState({bool? isListening, bool? isSpeaking, bool? isThinking}) {
    bool changed = false;

    if (isListening != null && _isListening != isListening) {
      _isListening = isListening;
      changed = true;
    }

    if (isSpeaking != null && _isSpeaking != isSpeaking) {
      _isSpeaking = isSpeaking;
      changed = true;
    }

    if (isThinking != null && _isThinking != isThinking) {
      _isThinking = isThinking;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _handleStateTransition() async {
    if (_state.tempSuggestedStory != null) {
      await _showStorySuggestions();
      return;
    }

    if (_state.currentStep == OnboardingStep.completion) {
      Log.d('✅ Onboarding completado', tag: 'CONV_CONTROLLER');
      return;
    }

    await generateNextAIMessage();
  }

  Future<void> _speakAndWaitForResponse(String text) async {
    if (text.trim().isEmpty) {
      Log.e(
        '🚨 Texto vacío detectado en TTS - Intento ${_ttsRetryCount + 1}/$_maxTtsRetries',
      );

      _ttsRetryCount++;
      if (_ttsRetryCount <= _maxTtsRetries) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _retryCurrentStep();
        return;
      } else {
        _ttsRetryCount = 0;
        const fallbackMessage =
            'Disculpa, hay un problema en mi sistema. Vamos a intentar continuar...';
        await _speakAndWaitForResponse(fallbackMessage);
        return;
      }
    }

    _ttsRetryCount = 0;
    _updateUIState(isSpeaking: true, isThinking: false);

    final voiceConfig = _voiceConfigService.getVoiceConfiguration(_state);

    Log.d('🗣️ Texto a sintetizar: "$text"', tag: 'CONV_CONTROLLER');
    Log.d('🔧 Config TTS: $voiceConfig', tag: 'CONV_CONTROLLER');

    try {
      final audioFilePath = await _ttsService.synthesizeToFile(
        text: text,
        options: {
          'voice': voiceConfig['voice'] as String? ?? 'marin',
          'model': voiceConfig['model'] as String?,
          'speed': voiceConfig['speed'] as double? ?? 1.0,
          'instructions': voiceConfig['instructions'] as String?,
          'provider': 'openai',
        },
      );

      if (audioFilePath != null) {
        Log.d('✅ TTS archivo generado: $audioFilePath', tag: 'CONV_CONTROLLER');

        final audioDuration = await AudioDurationUtils.getAudioDuration(
          audioFilePath,
        );

        _subtitleController.handleAiChunk(
          text,
          audioStarted: true,
          suppressFurther: false,
        );

        await _audioPlayer.play(DeviceFileSource(audioFilePath));

        if (audioDuration != null) {
          await Future.delayed(audioDuration);
        } else {
          final estimatedDuration = _estimateSpeechDuration(text);
          await Future.delayed(estimatedDuration);
        }
      } else {
        Log.w(
          '⚠️ TTS falló, continuando solo con subtítulos',
          tag: 'CONV_CONTROLLER',
        );
        _subtitleController.handleAiChunk(
          text,
          audioStarted: true,
          suppressFurther: false,
        );

        final estimatedDuration = _estimateSpeechDuration(text);
        await Future.delayed(estimatedDuration);
      }
    } catch (e) {
      Log.e('Error en TTS: $e', tag: 'CONV_CONTROLLER');
      _subtitleController.handleAiChunk(
        text,
        audioStarted: true,
        suppressFurther: false,
      );

      final estimatedDuration = _estimateSpeechDuration(text);
      await Future.delayed(estimatedDuration);
    }

    _updateUIState(isSpeaking: false, isThinking: false);
    await Future.delayed(const Duration(milliseconds: 300));
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_hybridSttService.isAvailable) return;

    _updateUIState(isListening: true);
    _speechTimeoutTimer?.cancel();

    await _hybridSttService.listen(
      onResult: (text) {
        Log.d('🗣️ Usuario dice: "$text"', tag: 'CONV_CONTROLLER');
        if (text.isNotEmpty) {
          _subtitleController.handleUserTranscription(text);
        }
        processUserResponse(text);
      },
      contextPrompt:
          'Conversación sobre nombres, fechas de nacimiento y países de origen.',
    );
  }

  Future<void> _retryCurrentStep() async {
    Log.d(
      '🔄 Reintentando paso actual: ${_state.currentStep.stepName}',
      tag: 'CONV_CONTROLLER',
    );
    await generateNextAIMessage();
  }

  Future<void> _showStorySuggestions() async {
    // Implementar lógica para mostrar sugerencias de historia
    final story =
        _state.tempSuggestedStory ?? 'Nos conocimos en una cafetería...';
    await _speakAndWaitForResponse('¿Qué te parece esta historia: $story?');
  }

  Duration _estimateSpeechDuration(String text) {
    // Estimación: ~150 palabras por minuto en español
    final wordCount = text.split(' ').length;
    final minutes = wordCount / 150.0;
    final milliseconds = (minutes * 60 * 1000).round();
    return Duration(milliseconds: milliseconds.clamp(1000, 30000));
  }
}
