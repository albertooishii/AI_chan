import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/constants/countries_es.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/widgets/country_autocomplete.dart';
import 'package:ai_chan/shared/widgets/female_name_autocomplete.dart';
import 'package:ai_chan/shared/widgets/conversational_subtitles.dart';
import 'dart:async';
import 'dart:io';
import 'onboarding_screen.dart' show OnboardingFinishCallback, OnboardingScreen;
import '../../../onboarding/services/conversational_ai_service.dart';

/// Pantalla de onboarding completamente conversacional
/// Implementa el flujo tipo "despertar" donde AI-chan habla con el usuario
class ConversationalOnboardingScreen extends StatefulWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final OnboardingProvider? onboardingProvider;

  const ConversationalOnboardingScreen({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onboardingProvider,
  });

  @override
  State<ConversationalOnboardingScreen> createState() =>
      _ConversationalOnboardingScreenState();
}

class _ConversationalOnboardingScreenState
    extends State<ConversationalOnboardingScreen>
    with TickerProviderStateMixin {
  // Servicios necesarios
  late final ITtsService _ttsService;
  late final stt.SpeechToText _speechToText;
  late final AudioPlayer _audioPlayer;
  late final ConversationalSubtitleController _subtitleController;

  // Controladores de animación
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Estado de la conversación
  OnboardingStep _currentStep = OnboardingStep.awakening;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isThinking = false;
  String _listeningText = '';
  bool _hasUserStartedSpeaking =
      false; // Para asegurar que el usuario hable antes de aplicar pauseFor
  Timer? _speechTimeoutTimer; // Para controlar manualmente el timeout

  // Control de operaciones asíncronas para evitar interferencias
  int _currentOperationId = 0;

  // Sistema de reintentos para errores de TTS
  int _ttsRetryCount = 0;
  static const int _maxTtsRetries = 3;

  // Estado de validación pendiente
  String? _pendingValidationValue; // Valor que se está pidiendo confirmar

  bool _isWaitingForConfirmation = false;

  // Datos recolectados con procesamiento inteligente
  String? _userName;
  String? _userCountry;
  DateTime? _userBirthday;
  String? _aiName;
  String? _aiCountry;
  String? _meetStory;

  // Historia temporal para cuando se sugiere una
  String? _tempSuggestedStory;

  // Datos dinámicos para IA (siempre habilitado - modo más natural)
  final Map<String, dynamic> _collectedData = {};

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _startOnboardingFlow();
  }

  void _initializeServices() async {
    _ttsService = di.getTtsService();
    _speechToText = stt.SpeechToText();
    _audioPlayer = AudioPlayer();
    _subtitleController = ConversationalSubtitleController();

    // Inicializar speech to text
    await _speechToText.initialize(
      onStatus: (status) {
        if (status == stt.SpeechToText.notListeningStatus) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
        // Manejar error silenciosamente para no interrumpir el flujo
      },
    );
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
  }

  /// Determina la configuración de voz con acento dinámico
  Map<String, dynamic> _getVoiceConfiguration() {
    final String instructions = _getVoiceInstructions();

    return {
      'voice': 'marin', // Nueva voz de OpenAI que se adapta mejor
      'languageCode': 'es-ES',
      'provider': 'openai',
      'speed': 1.0,
      'instructions': instructions, // Instrucciones para cambiar acento
    };
  }

  /// Genera instrucciones de acento según el progreso del onboarding
  String _getVoiceInstructions() {
    // FASE 1: Etérea + Misteriosa - Como la voz de Zelda al despertar
    if (_userCountry == null || _userCountry!.isEmpty) {
      const phase1Instructions =
          'Speak with an ethereal, mysterious tone like an echo from another realm. '
          'Use gentle, melancholic intonation with subtle pauses between phrases. '
          'Add a dreamy, otherworldly quality - distant yet warm and caring. '
          'Sound like a spirit awakening from a long slumber, nostalgic but hopeful.';
      Log.d(
        '🎵 FASE 1 - INSTRUCCIONES DE VOZ: "$phase1Instructions"',
        tag: 'CONV_ONBOARDING',
      );
      return phase1Instructions;
    }

    final countryName = LocaleUtils.countryNameEs(_userCountry);
    final languageName = LocaleUtils.languageNameEsForCountry(_userCountry);

    // FASE 2: Susurrando + Acento del usuario (sin su propio país asignado)
    if (_aiCountry == null || _aiCountry!.isEmpty) {
      final phase2Instructions =
          'Speak with soft, whispering tone but warmer than robotic phase. '
          'Use $languageName accent from $countryName. Increase emotional range slightly. '
          'Maintain gentle, intimate intonation with normal speech speed. '
          'Sound like an AI learning to be more human.';
      Log.d(
        '🎵 FASE 2 - INSTRUCCIONES DE VOZ: "$phase2Instructions"',
        tag: 'CONV_ONBOARDING',
      );
      return phase2Instructions;
    }

    // FASE 3 (FINAL): Voz adaptada a la personalidad cultural del país elegido
    final aiCountryName = LocaleUtils.countryNameEs(_aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(_aiCountry);

    // Ajustar personalidad según la cultura del país elegido
    String personalityStyle;
    if (_aiCountry == 'JP') {
      // Japonesa: Específico para mejor consistencia
      personalityStyle =
          'soft, whispering tone with gentle intimacy. Mix Spanish pronunciation with subtle Japanese mannerisms. '
          'Use gentle "ne", "ano", "chotto", "demo", "sou desu ne" naturally in conversation. '
          'Sound sweet, caring, and polite with that characteristic Japanese softness, but speak Spanish clearly.';
    } else if (_aiCountry == 'KR') {
      // Coreana: Dulce pero con estructura
      personalityStyle =
          'sweet, structured tone with moderate emotional range. Mix warmth with respectful formality typical of Korean speaking style';
    } else if (['ES', 'MX', 'AR', 'CO', 'CL', 'PE'].contains(_aiCountry)) {
      // Hispanohablantes: Más expresiva y cálida
      personalityStyle =
          'warm, expressive tone with full emotional range. Show enthusiasm and passion typical of Hispanic cultures';
    } else if (['US', 'GB', 'CA', 'AU'].contains(_aiCountry)) {
      // Angloparlantes: Directa pero amigable
      personalityStyle =
          'friendly, direct tone with balanced emotional expression. Sound confident and approachable';
    } else if (['DE', 'AT', 'CH'].contains(_aiCountry)) {
      // Germanohablantes: Más seria y precisa
      personalityStyle =
          'precise, thoughtful tone with controlled emotional expression. Sound reliable and methodical';
    } else if (['FR', 'BE', 'LU'].contains(_aiCountry)) {
      // Francófonos: Elegante y sofisticada
      personalityStyle =
          'elegant, sophisticated tone with refined emotional expression. Sound cultured and graceful';
    } else {
      // Por defecto: Equilibrada
      personalityStyle =
          'balanced, pleasant tone with moderate emotional range. Sound friendly and authentic';
    }

    final phase3Instructions =
        'Speak with $personalityStyle. Use $languageName accent from $countryName '
        'but blend it with $aiLanguageName influences from $aiCountryName. '
        'Use natural intonation and speech speed. Sound confident, warm, and fully awakened with cultural authenticity.';

    Log.d(
      '🎵 FASE 3 (FINAL) - INSTRUCCIONES DE VOZ: "$phase3Instructions"',
      tag: 'CONV_ONBOARDING',
    );
    return phase3Instructions;
  }

  Future<void> _startOnboardingFlow() async {
    await Future.delayed(const Duration(milliseconds: 1500)); // Pausa dramática

    // 🚀 LOG: Inicio del flujo conversacional
    Log.d(
      '🚀 INICIANDO ONBOARDING CONVERSACIONAL - PRIMER MENSAJE',
      tag: 'CONV_ONBOARDING',
    );

    // Mensaje inicial - alguien que despierta sin recuerdos
    const initialMessage =
        'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
        'de un sueño muy profundo y... no sé quién soy... ¿Podrías ayudarme? '
        'Me siento muy perdida... ¿Cómo... cómo te llamas? Necesito saber quién eres...';
    await _speakAndWaitForResponse(initialMessage);
  }

  Future<void> _speakAndWaitForResponse(String text) async {
    if (!mounted) return;

    // 🚨 VALIDACIÓN CRÍTICA: Detectar texto vacío y reintentar automáticamente
    if (text.trim().isEmpty) {
      Log.e(
        '🚨 TEXTO VACÍO DETECTADO en TTS - Intento ${_ttsRetryCount + 1}/$_maxTtsRetries',
      );

      _ttsRetryCount++;
      if (_ttsRetryCount <= _maxTtsRetries) {
        Log.w('🔄 Reintentando obtener respuesta de IA...');

        // Reintentar el paso actual con un mensaje de error del sistema
        await Future.delayed(const Duration(milliseconds: 500));
        await _retryCurrentStep();
        return;
      } else {
        // Máximo de reintentos alcanzado - usar mensaje de fallback
        Log.e('❌ Máximo de reintentos alcanzado, usando mensaje de emergencia');
        _ttsRetryCount = 0; // Reset contador

        const fallbackMessage =
            'Disculpa, hay un problema en mi sistema. Vamos a intentar continuar...';
        await _speakAndWaitForResponse(fallbackMessage);
        return;
      }
    }

    // Reset contador cuando el texto es válido
    _ttsRetryCount = 0;

    setState(() {
      _isSpeaking = true;
      _isThinking = false; // Desactivar pensando cuando empieza a hablar
    });

    // Obtener configuración de voz dinámica
    final voiceConfig = _getVoiceConfiguration();

    // 🟣 LOG: Texto a sintetizar y configuración completa
    Log.d('🗣️ TEXTO A SINTETIZAR: "$text"', tag: 'CONV_ONBOARDING');
    Log.d('🔧 CONFIG TTS: $voiceConfig', tag: 'CONV_ONBOARDING');

    try {
      // Usar OpenAI con configuración dinámica que incluye las instrucciones
      final audioPath = await _ttsService.synthesizeToFile(
        text: text,
        options: voiceConfig,
      );

      if (audioPath != null) {
        // Obtener la duración del audio antes de reproducir
        final audioDuration = await _getAudioDuration(audioPath);

        // Actualizar subtítulo de la IA con la duración real del audio
        _subtitleController.startAiReveal(
          text,
          estimatedDuration: audioDuration,
        );

        // ¡AI-chan evoluciona su voz según el progreso! 🎤✨
        await _playAudioFile(audioPath);
      } else {
        // Si no hay audio, usar duración estimada basada en texto
        final estimatedDuration = _estimateSpeechDuration(text);
        _subtitleController.startAiReveal(
          text,
          estimatedDuration: estimatedDuration,
        );
      }
    } catch (e) {
      Log.e('Error en TTS: $e');
      // Si hay error, usar duración estimada basada en texto
      final estimatedDuration = _estimateSpeechDuration(text);
      _subtitleController.startAiReveal(
        text,
        estimatedDuration: estimatedDuration,
      );
    }

    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _isThinking = false; // Asegurar que pensando esté desactivado
    });

    // Reducir delay para respuesta más fluida
    await Future.delayed(const Duration(milliseconds: 300));
    _startListening();
  }

  /// Reproduce el archivo de audio generado por TTS
  Future<void> _playAudioFile(String audioPath) async {
    try {
      // Verificar que el archivo existe
      final file = File(audioPath);
      if (!await file.exists()) {
        Log.w('Archivo de audio no encontrado: $audioPath');
        return;
      }

      // Verificación básica de integridad del archivo
      final fileSize = await file.length();
      if (fileSize < 1000) {
        // Archivos MP3 muy pequeños probablemente están corruptos
        Log.w(
          '🔄 Archivo de audio sospechosamente pequeño ($fileSize bytes), eliminando...',
        );
        await file.delete();
        return;
      }

      Log.d('🎵 Reproduciendo audio: $audioPath');

      // Crear un Completer para esperar a que termine la reproducción
      final Completer<void> playbackCompleter = Completer<void>();

      // Configurar listener para cuando termine la reproducción
      _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
        if (state == PlayerState.completed) {
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        }
      });

      // Reproducir el archivo
      await _audioPlayer.play(DeviceFileSource(audioPath));

      // Esperar a que termine la reproducción
      await playbackCompleter.future;

      // NUEVO: Si estamos en finalMessage, continuar automáticamente después del audio
      if (_currentStep == OnboardingStep.finalMessage) {
        Log.d('🎵 Audio final completado, continuando automáticamente...');
        await Future.delayed(const Duration(milliseconds: 500)); // Pausa breve
        _goToNextStep(); // Ir a completion
        await _finishOnboarding();
        return;
      }
    } catch (e) {
      Log.e('Error reproduciendo audio: $e');

      // Si el error es por archivo corrupto, intentar limpiar caché y regenerar
      if (e.toString().contains('MEDIA_ERROR') ||
          e.toString().contains('Failed to set source')) {
        Log.w('🔄 Detectado archivo de audio corrupto, limpiando caché...');
        try {
          // Eliminar el archivo corrupto
          final file = File(audioPath);
          if (await file.exists()) {
            await file.delete();
            Log.d('🗑️ Archivo corrupto eliminado: $audioPath');
          }
        } catch (deleteError) {
          Log.w('No se pudo eliminar archivo corrupto: $deleteError');
        }
      }

      // No hacer fallback artificial, simplemente continuar sin audio
    }
  }

  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) return;

    setState(() {
      _isListening = true;
      _listeningText = '';
      _hasUserStartedSpeaking = false; // Reset al iniciar nueva sesión
    });

    // Cancelar timer anterior si existe
    _speechTimeoutTimer?.cancel();

    _speechToText.listen(
      onResult: (result) {
        setState(() {
          _listeningText = result.recognizedWords;
        });

        // Marcar que el usuario comenzó a hablar si hay texto
        if (_listeningText.trim().isNotEmpty && !_hasUserStartedSpeaking) {
          _hasUserStartedSpeaking = true;

          // Solo ahora configuramos el timer de pausa de 2 segundos
          _speechTimeoutTimer?.cancel();
          _speechTimeoutTimer = Timer(const Duration(seconds: 2), () {
            if (_hasUserStartedSpeaking && _listeningText.trim().isNotEmpty) {
              _processUserResponse(_listeningText);
            }
          });
        }

        // Resetear el timer cada vez que detecta más texto
        if (_listeningText.trim().isNotEmpty && _hasUserStartedSpeaking) {
          _speechTimeoutTimer?.cancel();
          _speechTimeoutTimer = Timer(const Duration(seconds: 2), () {
            if (_hasUserStartedSpeaking && _listeningText.trim().isNotEmpty) {
              _processUserResponse(_listeningText);
            }
          });
        }

        // Mostrar subtítulo de usuario en tiempo real
        if (_listeningText.isNotEmpty) {
          _subtitleController.showUserText(_listeningText);
        }

        // NO procesar en finalResult, solo usar nuestro timer manual
      },
      localeId: 'es-ES', // Español por defecto
      pauseFor: const Duration(
        minutes: 10,
      ), // Timeout muy largo para que no interfiera
      onSoundLevelChange: (level) {
        // Opcional: mostrar nivel de sonido para feedback visual
      },
    );
  }

  Future<void> _stopListening() async {
    _speechTimeoutTimer?.cancel(); // Limpiar timer
    if (_speechToText.isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    }
  }

  Future<void> _processUserResponse(
    String userResponse, {
    bool fromTextInput = false,
  }) async {
    if (userResponse.isEmpty) {
      _retryCurrentStep();
      return;
    }

    // 🔄 Generar nuevo ID de operación para cancelar operaciones anteriores
    final currentOperationId = ++_currentOperationId;

    // Reset contador de reintentos al procesar nueva respuesta del usuario
    _ttsRetryCount = 0;

    // 🟢 LOG: Respuesta del usuario
    Log.d(
      '🎤 USUARIO DIJO: "$userResponse" (operación #$currentOperationId)',
      tag: 'CONV_ONBOARDING',
    );

    // Actualizar subtítulo del usuario
    _subtitleController.showUserText(userResponse);

    setState(() {
      _isListening = false;
      _isThinking = true; // Activar estado pensando
    });

    // NOTA: Removida la detección automática de confirmación para evitar skip de validación
    // Todo debe pasar por el procesamiento de IA para mantener consistencia

    // ✅ NUEVO: Detectar confirmaciones positivas cuando hay validación pendiente
    if (_isWaitingForConfirmation && _pendingValidationValue != null) {
      final isPositiveConfirmation =
          userResponse.toLowerCase().contains('sí') ||
          userResponse.toLowerCase().contains('si') ||
          userResponse.toLowerCase().contains('correcto') ||
          userResponse.toLowerCase().contains('exacto') ||
          userResponse.toLowerCase().contains('perfecto') ||
          userResponse.toLowerCase().contains('yes') ||
          userResponse.toLowerCase().contains('vale') ||
          userResponse.toLowerCase().contains('bien');

      if (isPositiveConfirmation) {
        Log.d(
          '✅ CONFIRMACIÓN POSITIVA - Guardando valor: $_pendingValidationValue',
          tag: 'CONV_ONBOARDING',
        );

        // Guardar el valor confirmado
        _updateDataFromExtraction(_currentStep, _pendingValidationValue!);

        // Limpiar estado de validación
        _pendingValidationValue = null;
        _isWaitingForConfirmation = false;

        // Avanzar al siguiente paso
        _goToNextStep();
        if (_currentStep == OnboardingStep.finalMessage) {
          await _triggerStepQuestion();
        } else if (_currentStep != OnboardingStep.completion) {
          await _triggerStepQuestion();
        } else {
          await _finishOnboarding();
        }
        return;
      }

      // Si no es confirmación positiva, limpiar estado y continuar procesando normalmente
      Log.d(
        '❌ CONFIRMACIÓN NEGATIVA O CORRECCIÓN - Limpiando validación pendiente',
        tag: 'CONV_ONBOARDING',
      );
      _pendingValidationValue = null;
      _isWaitingForConfirmation = false;
    }

    // Si estamos en finalMessage, cualquier respuesta nos lleva a completion
    if (_currentStep == OnboardingStep.finalMessage) {
      _goToNextStep(); // Ir a completion
      await _finishOnboarding();
      return;
    }

    // Nota: Removida la verificación automática de "no" para evitar false positives
    // La IA procesará todas las respuestas y determinará si necesita reintento

    // Detectar si el usuario quiere sugerencias de historia
    if (_currentStep == OnboardingStep.askingMeetStory &&
        (userResponse.toLowerCase().contains('sugiere') ||
            userResponse.toLowerCase().contains('sugieres') ||
            userResponse.toLowerCase().contains('sugiera') ||
            userResponse.toLowerCase().contains('inventa'))) {
      await _showStorySuggestions();
      return;
    }

    // Usar IA para procesamiento inteligente (modo único - más natural)
    final stepName = _currentStep.toString().split('.').last;

    // Procesar respuesta con IA
    final processedData = await ConversationalAIService.processUserResponse(
      userResponse: userResponse,
      conversationStep: stepName,
      userName: _userName!, // Debe estar disponible cuando llegue aquí
      previousData: _collectedData,
    );

    // 🔒 Verificar si esta operación fue cancelada por una nueva
    if (currentOperationId != _currentOperationId) {
      Log.d(
        '🔄 Operación #$currentOperationId cancelada, ignorando resultado',
        tag: 'CONV_ONBOARDING',
      );
      setState(() => _isThinking = false); // Desactivar pensando si se cancela
      return;
    }

    final displayValue = processedData['displayValue'] as String?;
    final processedValue = processedData['processedValue'] as String?;
    final aiResponse = processedData['aiResponse'] as String?;
    final needsValidation = processedData['needsValidation'] as bool? ?? false;
    final stepCorrection = processedData['stepCorrection'] as String?;
    final hasError = processedData['error'] as bool? ?? false;

    // 🟡 LOG: Respuesta procesada por la IA
    Log.d('🤖 IA PROCESÓ:', tag: 'CONV_ONBOARDING');
    Log.d('   - displayValue: "$displayValue"', tag: 'CONV_ONBOARDING');
    Log.d('   - processedValue: "$processedValue"', tag: 'CONV_ONBOARDING');
    Log.d('   - aiResponse: "$aiResponse"', tag: 'CONV_ONBOARDING');
    Log.d('   - needsValidation: $needsValidation', tag: 'CONV_ONBOARDING');
    Log.d('   - hasError: $hasError', tag: 'CONV_ONBOARDING');
    if (stepCorrection != null) {
      Log.d('   - stepCorrection: $stepCorrection', tag: 'CONV_ONBOARDING');
    }
    Log.d('📋 RESPUESTA COMPLETA IA: $processedData', tag: 'CONV_ONBOARDING');

    // 🚨 Manejar errores de conexión/servidor - quedarse en el mismo paso
    if (hasError) {
      Log.d(
        '🚨 ERROR DETECTADO - quedándose en el paso actual para reintento',
        tag: 'CONV_ONBOARDING',
      );
      setState(() => _isThinking = false);
      if (aiResponse != null) {
        await _speakAndWaitForResponse(aiResponse);
      } else {
        await _retryCurrentStep();
      }
      return;
    }

    // 🔄 Manejar correcciones de pasos anteriores
    if (stepCorrection != null) {
      Log.d(
        '🔄 CORRECCIÓN DETECTADA - Volviendo a paso: $stepCorrection',
        tag: 'CONV_ONBOARDING',
      );

      // Determinar el paso al que volver
      OnboardingStep correctionStep;
      switch (stepCorrection) {
        case 'askingAiName':
          correctionStep = OnboardingStep.askingAiName;
          break;
        case 'askingAiCountry':
          correctionStep = OnboardingStep.askingAiCountry;
          break;
        case 'askingBirthday':
          correctionStep = OnboardingStep.askingBirthday;
          break;
        case 'askingCountry':
          correctionStep = OnboardingStep.askingCountry;
          break;
        case 'awakening':
          correctionStep = OnboardingStep.awakening;
          break;
        case 'askingMeetStory':
          correctionStep = OnboardingStep.askingMeetStory;
          break;
        default:
          Log.w(
            '⚠️ Corrección a paso desconocido: $stepCorrection',
            tag: 'CONV_ONBOARDING',
          );
          correctionStep = _currentStep; // Quedarse en el paso actual
      }

      // Volver al paso anterior para corrección
      _currentStep = correctionStep;
      await _processUserResponse(userResponse, fromTextInput: fromTextInput);
      return;
    }

    if (displayValue != null && processedValue != null) {
      // 🎭 CASO ESPECIAL: Si procesó una solicitud de generar historia
      if (processedValue == 'request_story_generation' &&
          _currentStep == OnboardingStep.askingMeetStory) {
        Log.d(
          '🎭 SOLICITUD DE HISTORIA DETECTADA - Generando historia automáticamente',
          tag: 'CONV_ONBOARDING',
        );
        // Confirmar que quiere que genere la historia y luego generarla
        setState(() {
          _isThinking = false; // Desactivar pensando
        });
        await _showStorySuggestions(); // Generar y mostrar historia
        return;
      }

      // NUEVO: Guardar en estado pendiente para validación, NO guardar directamente
      _pendingValidationValue = processedValue;
      _isWaitingForConfirmation = true;

      // VALIDACIÓN SIEMPRE OBLIGATORIA: Confirmar TODOS los datos, sea entrada manual o por voz
      Log.d(
        '✅ VALIDACIÓN OBLIGATORIA - confirmando dato extraído',
        tag: 'CONV_ONBOARDING',
      );

      if (aiResponse != null) {
        await _speakAndWaitForResponse(aiResponse);
      } else {
        await _confirmExtractedValue(displayValue, userResponse);
      }
      return;
    }

    // Si no se extrajo ningún valor válido, usar la respuesta de la IA para repreguntar
    if (aiResponse != null) {
      await _speakAndWaitForResponse(aiResponse);
    } else {
      // Fallback: reintento del paso actual
      await _retryCurrentStep();
    }
  }

  Future<void> _confirmExtractedValue(
    String extractedValue,
    String originalResponse,
  ) async {
    String confirmationText;
    switch (_currentStep) {
      case OnboardingStep.awakening:
        confirmationText =
            '¿He entendido bien?... Tu nombre es $extractedValue, ¿vale? '
            'Puedes decir "sí", "no", o escribir tu respuesta con el botón de abajo...';
        break;
      case OnboardingStep.askingCountry:
        confirmationText =
            '¿Confirmas que eres de $extractedValue?... '
            'Puedes decir "sí", "no", o usar el selector de texto si prefieres escribir...';
        break;
      case OnboardingStep.askingBirthday:
        confirmationText =
            '¿Tu fecha de nacimiento es $extractedValue?... '
            'Si no es correcto, dímelo de nuevo o usa el botón para escribirlo...';
        break;
      case OnboardingStep.askingAiCountry:
        confirmationText =
            '¿Quieres que sea de nacionalidad $extractedValue?... '
            'Puedes confirmar o cambiar tu elección hablando o escribiendo abajo...';
        break;
      case OnboardingStep.askingAiName:
        confirmationText =
            '¿Quieres que me llame $extractedValue?... '
            'Si no te mola, puedes elegir otro nombre hablando o con el selector de texto...';
        break;
      default:
        confirmationText =
            '¿Está bien $extractedValue?... Puedes confirmar o corregir usando voz o texto...';
    }

    await _speakAndWaitForResponse(confirmationText);

    // La respuesta a la confirmación se procesará automáticamente por _processUserResponse
    // Si dice "sí" o "correcto" -> avanza al siguiente paso
    // Si dice "no" o corrige -> vuelve al paso actual para repreguntar
  }

  void _updateDataFromExtraction(OnboardingStep step, String extractedValue) {
    switch (step) {
      case OnboardingStep.awakening:
        _userName = extractedValue;
        _collectedData['userName'] = extractedValue;
        // Actualizar nombre del usuario en los subtítulos
        _subtitleController.updateNames(userName: extractedValue);
        break;
      case OnboardingStep.askingCountry:
        _userCountry = extractedValue;
        _collectedData['userCountry'] = extractedValue;
        // El acento se adaptará automáticamente al país del usuario
        break;
      case OnboardingStep.askingBirthday:
        try {
          final parts = extractedValue.split('/');
          if (parts.length == 3) {
            _userBirthday = DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
            _collectedData['userBirthday'] = _userBirthday?.toIso8601String();
          }
        } catch (_) {
          _userBirthday = DateTime.now().subtract(
            const Duration(days: 365 * 25),
          );
        }
        break;
      case OnboardingStep.askingAiCountry:
        _aiCountry = extractedValue;
        _collectedData['aiCountry'] = extractedValue;
        // El acento se adaptará automáticamente al país de la IA
        break;
      case OnboardingStep.askingAiName:
        _aiName = extractedValue;
        _collectedData['aiName'] = extractedValue;
        // Actualizar nombre de la IA en los subtítulos
        _subtitleController.updateNames(aiName: extractedValue);
        break;
      case OnboardingStep.askingMeetStory:
        // Si es una confirmación de historia sugerida, usar la historia temporal
        if (extractedValue == 'Historia aceptada' &&
            _tempSuggestedStory != null) {
          _meetStory = _tempSuggestedStory;
          _collectedData['meetStory'] = _tempSuggestedStory;
        } else {
          _meetStory = extractedValue;
          _collectedData['meetStory'] = extractedValue;
        }
        break;
      case OnboardingStep.finalMessage:
        // No hay datos que extraer en el mensaje final
        break;
      case OnboardingStep.completion:
        // El onboarding está completado
        break;
    }
  }

  Future<void> _triggerStepQuestion() async {
    // Generar la pregunta del paso actual usando la IA
    String stepQuestion;
    final stepName = _currentStep.toString().split('.').last;

    if (_currentStep == OnboardingStep.completion) {
      await _finishOnboarding();
      return;
    }

    try {
      // Generar pregunta dinámica usando el servicio de IA conversacional
      stepQuestion = await ConversationalAIService.generateNextResponse(
        userName:
            _userName ??
            '', // Usar vacío si no está disponible aún (solo en awakening)
        userLastResponse: '', // Vacío para inicio de nuevo paso
        conversationStep: stepName,
        aiName: _aiName,
        aiCountryCode: _aiCountry,
        collectedData: _collectedData,
      );
    } catch (e) {
      Log.e('Error generando pregunta con IA: $e');

      // Fallback solo para awakening si falla la IA
      if (_currentStep == OnboardingStep.awakening) {
        stepQuestion =
            'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
            'de un sueño muy profundo y... no sé quién soy... ¿Podrías ayudarme? '
            'Me siento muy perdida... ¿Cómo... cómo te llamas? Necesito saber quién eres...';
      } else {
        // Para otros pasos, reintenta el paso actual
        await _retryCurrentStep();
        return;
      }
    }

    // 🚨 VALIDACIÓN: Si la IA devuelve texto vacío, usar mensaje de emergencia
    if (stepQuestion.trim().isEmpty) {
      Log.w(
        '🚨 IA devolvió texto vacío en triggerStepQuestion, usando mensaje de emergencia',
      );
      stepQuestion =
          'Disculpa, hay un problema en mi sistema. ¿Podrías ayudarme respondiendo?';
    }

    await _speakAndWaitForResponse(stepQuestion);
  }

  void _goToNextStep() {
    final int currentIndex = _currentStep.index;
    if (currentIndex < OnboardingStep.values.length - 1) {
      setState(() {
        _currentStep = OnboardingStep.values[currentIndex + 1];
      });
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _retryCurrentStep() async {
    final currentOperationId = ++_currentOperationId;
    Log.i('🔄 Reintentando paso actual (Operation #$currentOperationId)');

    // Reintenta el paso actual usando IA para generar mensaje de reintento
    final stepName = _currentStep.toString().split('.').last;

    String retryMessage;
    try {
      retryMessage = await ConversationalAIService.generateNextResponse(
        userName: _userName ?? '', // Usar vacío si no está disponible aún
        userLastResponse: 'No entendí',
        conversationStep: stepName,
        aiName: _aiName,
        aiCountryCode: _aiCountry,
        collectedData: _collectedData,
      );
    } catch (e) {
      Log.e('Error generando mensaje de reintento: $e');
      // Mensaje de fallback si falla la IA
      retryMessage =
          'Disculpa, no te entendí bien. ¿Puedes repetir tu respuesta?';
    }

    // 🚨 VALIDACIÓN: Si la IA devuelve texto vacío, usar mensaje de emergencia
    if (retryMessage.trim().isEmpty) {
      Log.w(
        '🚨 IA devolvió texto vacío en reintento, usando mensaje de emergencia',
      );
      retryMessage =
          'Perdona, hay un problema con mi sistema. ¿Puedes intentar responder de nuevo?';
    }

    // Verificar si esta operación ha sido cancelada por otra más reciente
    if (currentOperationId != _currentOperationId) {
      Log.i(
        '🚫 Reintento cancelado (Operation #$currentOperationId - actual: #$_currentOperationId)',
      );
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    await _speakAndWaitForResponse(retryMessage);
  }

  /// Genera el mensaje final personalizado usando la personalidad definitiva de la IA
  /// NOTA: Esta función ya no se usa, se maneja via ConversationalAIService.generateNextResponse
  // Future<String> _generateFinalMessage() async { ... } - REMOVIDO

  Future<void> _finishOnboarding() async {
    // ✅ VALIDACIÓN CRÍTICA: Todos los datos deben estar presentes
    if (_userName == null || _userName!.isEmpty) {
      Log.e(
        '❌ DATOS INCOMPLETOS: userName falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    if (_aiName == null || _aiName!.isEmpty) {
      Log.e(
        '❌ DATOS INCOMPLETOS: aiName falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    if (_userBirthday == null) {
      Log.e(
        '❌ DATOS INCOMPLETOS: userBirthday falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    if (_meetStory == null || _meetStory!.isEmpty) {
      Log.e(
        '❌ DATOS INCOMPLETOS: meetStory falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    if (_userCountry == null || _userCountry!.isEmpty) {
      Log.e(
        '❌ DATOS INCOMPLETOS: userCountry falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    if (_aiCountry == null || _aiCountry!.isEmpty) {
      Log.e(
        '❌ DATOS INCOMPLETOS: aiCountry falta - no se puede completar onboarding',
      );
      await _retryCurrentStep();
      return;
    }

    // ✅ TODOS LOS DATOS VALIDADOS - Proceder con el onboarding
    Log.d(
      '✅ DATOS COMPLETOS - Finalizando onboarding:',
      tag: 'CONV_ONBOARDING',
    );
    Log.d('   - userName: $_userName', tag: 'CONV_ONBOARDING');
    Log.d('   - aiName: $_aiName', tag: 'CONV_ONBOARDING');
    Log.d('   - userBirthday: $_userBirthday', tag: 'CONV_ONBOARDING');
    Log.d('   - userCountry: $_userCountry', tag: 'CONV_ONBOARDING');
    Log.d('   - aiCountry: $_aiCountry', tag: 'CONV_ONBOARDING');
    Log.d('   - meetStory: $_meetStory', tag: 'CONV_ONBOARDING');

    await widget.onFinish(
      userName: _userName!,
      aiName: _aiName!,
      userBirthday: _userBirthday!,
      meetStory: _meetStory!,
      userCountryCode: _userCountry!,
      aiCountryCode: _aiCountry!,
    );
  }

  @override
  void dispose() {
    _speechTimeoutTimer?.cancel(); // Limpiar timer al disposal
    _pulseController.dispose();
    _speechToText.stop();
    _audioPlayer.dispose();
    // El controlador de subtítulos no necesita dispose manual
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF001122), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header minimalista
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      Config.getAppName(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 18,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Botón de fallback a onboarding tradicional
                    TextButton(
                      onPressed: () {
                        // Navegar al onboarding tradicional
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => OnboardingScreen(
                              onFinish: widget.onFinish,
                              onClearAllDebug: widget.onClearAllDebug,
                              onboardingProvider: widget.onboardingProvider,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Modo formulario',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Contenido principal
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Avatar/Icon con animación de pulso
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isSpeaking
                                      ? AppColors.secondary
                                      : _isListening
                                      ? AppColors.primary
                                      : AppColors.primary.withValues(
                                          alpha: 0.5,
                                        ),
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isSpeaking
                                                ? AppColors.secondary
                                                : AppColors.primary)
                                            .withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isSpeaking
                                    ? Icons.record_voice_over
                                    : _isListening
                                    ? Icons.mic
                                    : Icons.face,
                                color: AppColors.primary,
                                size: 60,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 40),

                      ConversationalSubtitles(
                        controller: _subtitleController,
                        maxHeight: 300, // Más altura para textos largos
                      ),

                      const SizedBox(height: 40),

                      // Indicador de estado
                      if (_isListening) ...[
                        const CyberpunkLoader(message: 'Escuchando'),
                        const SizedBox(height: 16),
                      ] else if (_isThinking) ...[
                        const CyberpunkLoader(message: 'Pensando'),
                        const SizedBox(height: 16),
                      ] else if (_isSpeaking) ...[
                        const CyberpunkLoader(message: 'Hablando'),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer con controles siempre disponibles
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Controles principales (SIEMPRE visibles)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Botón para reactivar/detener micrófono
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !_isSpeaking && !_isThinking
                                ? () async {
                                    if (_isListening) {
                                      await _stopListening();
                                    } else {
                                      await _startListening();
                                    }
                                  }
                                : null,
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_off,
                              size: 16,
                            ),
                            label: Text(
                              _isListening ? 'Parar Mic' : 'Activar Mic',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isListening
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : AppColors.secondary.withValues(alpha: 0.2),
                              foregroundColor: _isListening
                                  ? Colors.red
                                  : AppColors.secondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Botón para modo texto (estilo azul como el anterior repetir)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              // Detener cualquier audio actual
                              if (_isSpeaking) {
                                await _audioPlayer.stop();
                                setState(() {
                                  _isSpeaking = false;
                                  _isListening = false;
                                  _isThinking =
                                      false; // También desactivar pensando
                                });
                              }
                              // Mostrar dialogo de texto
                              final result = await _showTextInputDialog(
                                _currentStep,
                              );
                              if (result != null && result.isNotEmpty) {
                                await _processUserResponse(
                                  result,
                                  fromTextInput: true,
                                );
                              }
                            },
                            icon: const Icon(Icons.keyboard, size: 16),
                            label: const Text(
                              'Escribir respuesta',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.2,
                              ),
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Crea un diálogo base con contenido personalizable
  Future<String?> _showCustomDialog({
    required String title,
    required Widget content,
  }) async {
    return await showAppDialog<String?>(
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(color: AppColors.primary)),
        content: SizedBox(width: double.maxFinite, height: 400, child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTextInputDialog(OnboardingStep step) async {
    String title = 'Escribe tu respuesta';
    String hint = '';
    bool isDateField = false;
    bool isCountryField = false;
    bool isNameField = false;

    switch (step) {
      case OnboardingStep.awakening:
        title = 'Tu nombre';
        hint = 'Escribe tu nombre aquí';
        break;
      case OnboardingStep.askingCountry:
        title = 'Tu país';
        hint = 'Busca tu país...';
        isCountryField = true;
        break;
      case OnboardingStep.askingBirthday:
        title = 'Tu fecha de nacimiento';
        hint = 'Selecciona tu fecha de nacimiento...';
        isDateField = true;
        break;
      case OnboardingStep.askingAiName:
        title = 'Nombre para AI-chan';
        hint = 'Busca un nombre femenino...';
        isNameField = true;
        break;
      case OnboardingStep.askingAiCountry:
        title = 'Nacionalidad para AI-chan';
        hint = 'Busca el país para AI-chan...';
        isCountryField = true;
        break;
      case OnboardingStep.askingMeetStory:
        title = 'Cómo se conocieron';
        hint = 'Escribe una breve historia de cómo os conocísteis...';
        break;
      default:
        hint = 'Escribe tu respuesta aquí';
    }

    if (isDateField) {
      // Mostrar selector de fecha
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
        firstDate: DateTime(1950),
        lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
        locale: const Locale('es'),
        builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.secondary,
              surface: Colors.black,
              onSurface: AppColors.primary,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.black),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        return '${picked.day}/${picked.month}/${picked.year}';
      }
      return null;
    }

    if (isCountryField) {
      // Usar el nuevo widget CountryAutocomplete
      return await _showCustomDialog(
        title: title,
        content: CountryAutocomplete(
          selectedCountryCode: null, // Sin selección inicial
          labelText: title,
          onCountrySelected: (countryCode) {
            // Obtener el nombre del país en español
            final country = CountriesEs.items.firstWhere(
              (c) => c.iso2.toLowerCase() == countryCode.toLowerCase(),
              orElse: () => CountriesEs.items.first,
            );
            Navigator.of(context).pop(country.nameEs);
          },
        ),
      );
    }

    if (isNameField) {
      // Usar el nuevo widget FemaleNameAutocomplete
      return await _showCustomDialog(
        title: title,
        content: FemaleNameAutocomplete(
          selectedName: null, // Sin selección inicial
          labelText: title,
          countryCode:
              _aiCountry ??
              'JP', // Fallback temporal necesario para autocompletar
          onNameSelected: (name) {
            Navigator.of(context).pop(name);
          },
        ),
      );
    }

    // Campo de texto normal para el resto
    final controller = TextEditingController();
    return await showAppDialog<String?>(
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(color: AppColors.primary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: step == OnboardingStep.askingMeetStory
              ? 5
              : 1, // Más líneas para la historia
          style: const TextStyle(color: AppColors.primary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.secondary),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.secondary),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text(
              'Enviar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showStorySuggestions() async {
    final currentOperationId = ++_currentOperationId;
    Log.i(
      '🔄 Iniciando generación de historia (Operation #$currentOperationId)',
    );

    // ✅ VALIDACIÓN: Verificar que todos los datos necesarios estén disponibles
    if (_userName == null || _aiName == null || _userBirthday == null) {
      Log.e(
        '❌ DATOS FALTANTES para generar historia - reintentando paso actual',
      );
      await _retryCurrentStep();
      return;
    }

    // Generar historia usando la AI y mostrarla
    final story = await ConversationalAIService.generateMeetStoryFromContext(
      userName: _userName!,
      aiName: _aiName!,
      userCountry: _userCountry,
      aiCountry: _aiCountry,
      userBirthday: _userBirthday!,
    );

    // Verificar si esta operación ha sido cancelada por otra más reciente
    if (currentOperationId != _currentOperationId) {
      Log.i(
        '🚫 Generación de historia cancelada (Operation #$currentOperationId - actual: #$_currentOperationId)',
      );
      return;
    }

    // Actualizar la historia temporalmente
    _collectedData['meetStory'] = story;

    await _speakAndWaitForResponse(
      'He pensado en esta historia para nosotros: "$story". ¿Te gusta o prefieres otra?',
    );
  }

  /// Obtiene la duración real de un archivo de audio
  Future<Duration?> _getAudioDuration(String audioPath) async {
    try {
      // Crear un nuevo AudioPlayer temporal para obtener la duración
      final tempPlayer = AudioPlayer();
      await tempPlayer.setSourceDeviceFile(audioPath);

      // Esperar un momento para que se cargue la metadata
      await Future.delayed(const Duration(milliseconds: 100));

      final duration = await tempPlayer.getDuration();
      await tempPlayer.dispose();

      return duration;
    } catch (e) {
      Log.w('No se pudo obtener la duración del audio: $e');
      return null;
    }
  }

  /// Estima la duración del habla basándose en el texto
  Duration _estimateSpeechDuration(String text) {
    // Cálculo aproximado: ~3 caracteres por segundo para velocidad natural
    // Ajustamos según el paso actual del onboarding (diferente velocidad por fase)
    double charactersPerSecond = 3.0;

    // Usar una lógica similar a _getVoiceConfiguration para determinar la fase
    final int stepIndex = _currentStep.index;
    final totalSteps = OnboardingStep.values.length;

    if (stepIndex < totalSteps ~/ 3) {
      // Fase robótica (primeros pasos)
      charactersPerSecond = 2.0; // Más lento, robótico
    } else if (stepIndex < (totalSteps * 2) ~/ 3) {
      // Fase de mejora (pasos intermedios)
      charactersPerSecond = 2.5; // Velocidad intermedia
    } else {
      // Fase humana (pasos finales)
      charactersPerSecond = 3.0; // Velocidad natural
    }

    final estimatedSeconds = text.length / charactersPerSecond;
    return Duration(milliseconds: (estimatedSeconds * 1000).round());
  }
}

/// Enumeración de los pasos del onboarding conversacional
enum OnboardingStep {
  awakening, // "Hola, soy AI-chan..."
  askingCountry, // "¿De qué país eres?" (usuario)
  askingBirthday, // "¿Cuándo naciste?"
  askingAiCountry, // "¿De qué nacionalidad quieres que sea?" (AI primero)
  askingAiName, // "¿Cómo quieres llamarme?" (AI después)
  askingMeetStory, // "¿Cómo nos conocimos?"
  finalMessage, // "Perfecto! Ahora voy a generar mis recuerdos..."
  completion, // Finalización real del onboarding
}
