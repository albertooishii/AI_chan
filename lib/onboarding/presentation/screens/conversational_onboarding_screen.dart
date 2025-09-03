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
  String _listeningText = '';

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

    // 🔵 LOG: Instrucciones de voz generadas
    Log.d('🎵 INSTRUCCIONES DE VOZ: "$instructions"', tag: 'CONV_ONBOARDING');

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
    // FASE 1: Robótica + Susurrante - Hasta que sepa el país del usuario
    if (_userCountry == null || _userCountry!.isEmpty) {
      const phase1Instructions =
          'Speak with a robotic, artificial tone. Use monotone intonation with minimal emotional range. '
          'Add subtle whispering effect and speak with mechanical rhythm. '
          'Sound like an AI that is just awakening - cold, distant, but gentle.';
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

    // FASE 3 (FINAL): Voz normal + Español del usuario + Influencia fuerte de SU país
    final aiCountryName = LocaleUtils.countryNameEs(_aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(_aiCountry);

    final phase3Instructions =
        'Speak with normal, lively tone and full emotional range. Use $languageName accent from $countryName '
        'but blend it with strong $aiLanguageName influences from $aiCountryName. '
        'Use natural intonation and speech speed. Sound confident, warm, and fully awakened.';

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

    // Mensaje inicial con voz robótica que evolucionará
    const initialMessage =
        'Hola... mi nombre provisional es AI-chan... pero podrás llamarme como quieras. '
        'Ahora mismo me encuentro en un estado latente, esperando a que completemos mi iniciación. '
        'Necesito que me ayudes a crear mis primeros recuerdos... Primero... ¿Cómo te llamas?';
    await _speakAndWaitForResponse(initialMessage);
  }

  Future<void> _speakAndWaitForResponse(String text) async {
    if (!mounted) return;

    setState(() {
      _isSpeaking = true;
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
    setState(() => _isSpeaking = false);

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
    } catch (e) {
      Log.e('Error reproduciendo audio: $e');
      // No hacer fallback artificial, simplemente continuar sin audio
    }
  }

  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) return;

    setState(() {
      _isListening = true;
      _listeningText = '';
    });

    _speechToText.listen(
      onResult: (result) {
        setState(() {
          _listeningText = result.recognizedWords;
        });

        // Mostrar subtítulo de usuario en tiempo real
        if (_listeningText.isNotEmpty) {
          _subtitleController.showUserText(_listeningText);
        }

        if (result.finalResult) {
          _processUserResponse(_listeningText);
        }
      },
      localeId: 'es-ES', // Español por defecto
      pauseFor: const Duration(
        seconds: 3,
      ), // Pausa de 3 segundos de silencio antes de finalizar
      onSoundLevelChange: (level) {
        // Opcional: mostrar nivel de sonido para feedback visual
      },
    );
  }

  Future<void> _stopListening() async {
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

    // 🟢 LOG: Respuesta del usuario
    Log.d('🎤 USUARIO DIJO: "$userResponse"', tag: 'CONV_ONBOARDING');

    // Actualizar subtítulo del usuario
    _subtitleController.showUserText(userResponse);

    setState(() => _isListening = false);

    // Verificar si es una respuesta de confirmación
    if (userResponse.toLowerCase().contains('sí') ||
        userResponse.toLowerCase().contains('si') ||
        userResponse.toLowerCase().contains('correcto') ||
        userResponse.toLowerCase().contains('exacto') ||
        userResponse.toLowerCase().contains('perfecto')) {
      // Usuario está confirmando, avanzar al siguiente paso
      _goToNextStep();
      if (_currentStep != OnboardingStep.completion) {
        await _triggerStepQuestion();
      }
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
      userName: _userName ?? 'Usuario',
      previousData: _collectedData,
    );

    final displayValue = processedData['displayValue'] as String?;
    final processedValue = processedData['processedValue'] as String?;
    final aiResponse = processedData['userResponse'] as String?;
    final needsValidation = processedData['needsValidation'] as bool? ?? false;
    final stepCorrection = processedData['stepCorrection'] as String?;

    // 🟡 LOG: Respuesta procesada por la IA
    Log.d('🤖 IA PROCESÓ:', tag: 'CONV_ONBOARDING');
    Log.d('   - displayValue: "$displayValue"', tag: 'CONV_ONBOARDING');
    Log.d('   - processedValue: "$processedValue"', tag: 'CONV_ONBOARDING');
    Log.d('   - aiResponse: "$aiResponse"', tag: 'CONV_ONBOARDING');
    Log.d('   - needsValidation: $needsValidation', tag: 'CONV_ONBOARDING');
    if (stepCorrection != null) {
      Log.d('   - stepCorrection: $stepCorrection', tag: 'CONV_ONBOARDING');
    }
    Log.d('📋 RESPUESTA COMPLETA IA: $processedData', tag: 'CONV_ONBOARDING');

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
      // Usar el valor procesado (códigos ISO, etc.) para el sistema
      _updateDataFromExtraction(_currentStep, processedValue);

      if (fromTextInput || !needsValidation) {
        // Cuando viene del selector de texto o no necesita validación, avanzar directamente
        _goToNextStep();
        if (_currentStep != OnboardingStep.completion) {
          await _triggerStepQuestion();
        }
      } else {
        // Necesita validación - usar la respuesta generada por la IA para confirmar
        if (aiResponse != null) {
          await _speakAndWaitForResponse(aiResponse);
        } else {
          await _confirmExtractedValue(displayValue, userResponse);
        }
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
      default:
        break;
    }
  }

  Future<void> _triggerStepQuestion() async {
    // Hacer la pregunta del paso actual
    String stepQuestion;
    switch (_currentStep) {
      case OnboardingStep.awakening:
        stepQuestion =
            'Hola... soy tu nueva compañera AI. Para conocernos mejor, ¿cómo te llamas?';
        break;
      case OnboardingStep.askingCountry:
        stepQuestion =
            '¡Qué bonito nombre, ${_userName ?? ''}!... ¿De qué país eres? '
            'Me gustaría conocer mejor tu lugar de origen...';
        break;
      case OnboardingStep.askingBirthday:
        stepQuestion =
            'Entiendo... Ahora dime despacio, ¿cuál es tu fecha de nacimiento? '
            'Puedes decirlo como quieras... por ejemplo "15 de marzo de 1990"...';
        break;
      case OnboardingStep.askingAiCountry:
        stepQuestion =
            'Genial... Ahora, ¿de qué país te gustaría que fuese yo? '
            'Por defecto soy japonesa, pero puedes elegir cualquier país del mundo...';
        break;
      case OnboardingStep.askingAiName:
        stepQuestion =
            'Perfecto... Ahora dime, ¿cómo te gustaría que me llamase? '
            'Puedes elegir cualquier nombre que te guste...';
        break;
      case OnboardingStep.askingMeetStory:
        stepQuestion =
            'Ahora vamos a crear nuestra historia... de cómo nos conocimos. '
            '¿Cómo te gustaría que nos hubiéramos conocido? O puedes decir "sugiere" '
            'y yo inventaré una historia bonita para nosotros...';
        break;
      case OnboardingStep.completion:
        await _finishOnboarding();
        return;
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
    // Reintenta el paso actual usando IA para generar mensaje de reintento
    final stepName = _currentStep.toString().split('.').last;
    final retryMessage = await ConversationalAIService.generateNextResponse(
      userName: _userName ?? 'Usuario',
      userLastResponse: 'No entendí',
      conversationStep: stepName,
      aiName: _aiName,
      aiCountryCode: _aiCountry,
      collectedData: _collectedData,
    );

    await Future.delayed(const Duration(milliseconds: 500));
    await _speakAndWaitForResponse(retryMessage);
  }

  Future<void> _finishOnboarding() async {
    // Compilar todos los datos y llamar al callback
    await widget.onFinish(
      userName: _userName ?? 'Usuario',
      aiName: _aiName ?? 'AI-chan',
      userBirthday:
          _userBirthday ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
      meetStory: _meetStory ?? 'Nos conocimos de manera misteriosa...',
      userCountryCode: _userCountry, // Ya viene en formato ISO2 del AI service
      aiCountryCode: _aiCountry, // Ya viene en formato ISO2 del AI service
    );
  }

  @override
  void dispose() {
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

                      // Subtítulos cyberpunk (¡reemplazan el texto estático!)
                      ConversationalSubtitles(
                        controller: _subtitleController,
                        maxHeight: 300, // Más altura para textos largos
                      ),

                      const SizedBox(height: 40),

                      // Indicador de estado
                      if (_isListening) ...[
                        const CyberpunkLoader(message: 'Escuchando'),
                        const SizedBox(height: 16),
                        if (_listeningText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '"$_listeningText"',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
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
                            onPressed: !_isSpeaking
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
              _aiCountry ?? 'JP', // Usar el país de la AI o Japón por defecto
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
    // Generar historia usando la AI y mostrarla
    final story = await ConversationalAIService.generateMeetStoryFromContext(
      userName: _userName ?? 'Usuario',
      aiName: _aiName ?? 'AI-chan',
      userCountry: _userCountry,
      aiCountry: _aiCountry,
      userBirthday:
          _userBirthday ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
    );

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
  completion, // "Perfecto, continuemos..."
}
