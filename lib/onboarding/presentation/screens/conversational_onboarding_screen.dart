import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/onboarding/services/conversational_ai_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/services/openai_tts_service.dart';
import 'package:ai_chan/shared/services/hybrid_stt_service.dart';
import 'package:ai_chan/shared/controllers/audio_subtitle_controller.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/widgets/conversational_subtitles.dart';
import 'dart:async';
import 'onboarding_screen.dart' show OnboardingFinishCallback, OnboardingScreen;

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
  late final OpenAITtsService _openaiTtsService;
  late final HybridSttService _hybridSttService;
  late final AudioPlayer _audioPlayer;
  late final ConversationalSubtitleController _subtitleController;
  late final AudioSubtitleController _progressiveSubtitleController;

  // Controladores de animación
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Estado de la conversación
  OnboardingStep _currentStep = OnboardingStep.awakening;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isTtsPlaying = false;
  bool _isThinking = false;
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
    _openaiTtsService = OpenAITtsService();
    _hybridSttService = HybridSttService();
    _audioPlayer = AudioPlayer();
    _subtitleController = ConversationalSubtitleController();
    _progressiveSubtitleController = AudioSubtitleController();

    // Inicializar hybrid STT
    await _hybridSttService.initialize(
      onStatus: (status) {
        Log.d(
          '📢 STT Status: $status (${_hybridSttService.isUsingOpenAI ? "OpenAI" : "Native"})',
          tag: 'CONV_ONBOARDING',
        );
        if (status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        Log.e('STT Error: $error', tag: 'CONV_ONBOARDING');
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
    // Tono base consistente: suave, íntimo, vulnerable pero esperanzado
    const baseTone =
        'Mantén una entonación tierna y cariñosa en todo momento. Suena esperanzada pero aún un poco perdida y necesitando ayuda.';

    // FASE 1: Acento neutro robótico
    if (_userCountry == null || _userCountry!.isEmpty) {
      const phase1Instructions =
          '$baseTone Usa un acento neutro, ligeramente robótico - como si aún estuvieras aprendiendo a hablar de forma natural. Sin acento regional todavía, solo pronunciación clara en español.';
      Log.d(
        '🎵 FASE 1 - INSTRUCCIONES DE VOZ: "$phase1Instructions"',
        tag: 'CONV_ONBOARDING',
      );
      return phase1Instructions;
    }

    final countryName = LocaleUtils.countryNameEs(_userCountry);
    final languageName = LocaleUtils.languageNameEsForCountry(_userCountry);

    // FASE 2: Acento del país del usuario
    if (_aiCountry == null || _aiCountry!.isEmpty) {
      final phase2Instructions =
          '$baseTone Usa acento $languageName de $countryName. Tus patrones de habla ahora reflejan el acento regional del usuario mientras aprendes de él.';
      Log.d(
        '🎵 FASE 2 - INSTRUCCIONES DE VOZ: "$phase2Instructions"',
        tag: 'CONV_ONBOARDING',
      );
      return phase2Instructions;
    }

    // FASE 3 (FINAL): Acento del país de la IA
    final aiCountryName = LocaleUtils.countryNameEs(_aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(_aiCountry);

    // Verificar si el país de la IA habla español nativamente
    final spanishSpeakingCountries = LocaleUtils.speakSpanish();
    final isSpanishNative = spanishSpeakingCountries.contains(
      _aiCountry!.toUpperCase(),
    );

    // Crear instrucción diferente según si es hispanohablante nativo o no
    final String accentInstructions;
    if (isSpanishNative) {
      // País hispanohablante: español nativo con acento regional
      accentInstructions =
          'Habla español nativo con acento de $aiCountryName. '
          'Usa la pronunciación y entonación natural de una persona nacida en $aiCountryName.';
    } else {
      // País no hispanohablante: español con acento del idioma original
      accentInstructions =
          'Habla español con acento $aiLanguageName de $aiCountryName. '
          'Pronuncia el español como una persona nativa de $aiCountryName que aprendió español como segundo idioma, '
          'manteniendo el acento y patrones de habla de su idioma original.';
    }

    final phase3Instructions = '$baseTone $accentInstructions';

    Log.d(
      '🎵 FASE 3 (FINAL) - INSTRUCCIONES DE VOZ: "$phase3Instructions"',
      tag: 'CONV_ONBOARDING',
    );
    return phase3Instructions;
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
      // Usar OpenAI TTS directo con subtítulos progresivos
      Log.d(
        '🚀 Usando OpenAI TTS directo con subtítulos progresivos...',
        tag: 'CONV_ONBOARDING',
      );

      final audioInfo = await _openaiTtsService.synthesizeAndPlay(
        text,
        options: voiceConfig,
      );

      if (audioInfo != null) {
        Log.d(
          '✅ Audio generado, iniciando subtítulos progresivos',
          tag: 'CONV_ONBOARDING',
        );

        // 📝 CONFIGURAR SUBTÍTULOS PROGRESIVOS (como en audio_message_player_with_subs.dart)
        _progressiveSubtitleController.updateProportional(
          Duration.zero,
          text,
          audioInfo.duration,
        );

        // 🎬 SUSCRIBIRSE AL STREAM PROGRESIVO
        late StreamSubscription<String> progressSub;
        progressSub = _progressiveSubtitleController.progressiveTextStream
            .listen((progressiveText) {
              if (progressiveText.isNotEmpty && mounted) {
                _subtitleController.handleAiChunk(
                  progressiveText,
                  audioStarted: true,
                  suppressFurther: false,
                );
              }
            });

        // ⏰ SIMULAR PROGRESO DE TIEMPO (como en audio_message_player_with_subs.dart)
        const updateInterval = Duration(milliseconds: 100);
        const revealDelay = Duration(
          milliseconds: 500,
        ); // Delay inicial para evitar flash
        final adjustedDuration = audioInfo.duration - revealDelay;

        Timer.periodic(updateInterval, (timer) {
          if (!mounted || !_isSpeaking) {
            timer.cancel();
            progressSub.cancel();
            return;
          }

          final elapsed = Duration(
            milliseconds: timer.tick * updateInterval.inMilliseconds,
          );

          if (elapsed <= revealDelay) {
            // Durante el delay inicial: mantener subtítulos limpios
            _subtitleController.clearAll();
          } else if (elapsed >= audioInfo.duration) {
            // Al final: mostrar texto completo y limpiar
            timer.cancel();
            progressSub.cancel();
            _subtitleController.handleAiChunk(
              text,
              audioStarted: true,
              suppressFurther: false,
            );
          } else {
            // Progreso normal: actualizar posición proporcional
            final effectiveElapsed = elapsed - revealDelay;
            _progressiveSubtitleController.updateProportional(
              effectiveElapsed,
              text,
              adjustedDuration,
            );
          }
        });

        // ⏳ ESPERAR A QUE TERMINE LA REPRODUCCIÓN
        await _openaiTtsService.waitForCompletion();

        // Limpiar suscripción si aún está activa
        progressSub.cancel();

        Log.d(
          '✅ OpenAI TTS con subtítulos progresivos completado exitosamente',
          tag: 'CONV_ONBOARDING',
        );
      } else {
        // Fallback si no hay información de audio
        _subtitleController.handleAiChunk(
          text,
          audioStarted: true,
          suppressFurther: false,
        );
      }
    } catch (e) {
      Log.e('❌ Error en OpenAI TTS: $e', tag: 'CONV_ONBOARDING');

      // En caso de error, mostrar texto completo inmediatamente
      _subtitleController.handleAiChunk(
        text,
        audioStarted: true,
        suppressFurther: false,
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

  Future<void> _startListening() async {
    if (!_hybridSttService.isAvailable) return;

    setState(() {
      _isListening = true;
    });

    // Cancelar timer anterior si existe
    _speechTimeoutTimer?.cancel();

    await _hybridSttService.listen(
      onResult: (text) {
        setState(() {
          Log.d('🗣️ Usuario dice: "$text"', tag: 'CONV_ONBOARDING');
        });

        // Mostrar subtítulo en tiempo real del usuario
        if (text.isNotEmpty) {
          _subtitleController.handleUserTranscription(text);
        }

        // Procesar resultado final (el híbrido ya maneja finalizaciones)
        _processUserResponse(text);
      },
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> _stopListening() async {
    _speechTimeoutTimer?.cancel(); // Limpiar timer
    if (_hybridSttService.isListening) {
      await _hybridSttService.stop();
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
    _subtitleController.handleUserTranscription(userResponse);

    setState(() {
      _isListening = false;
      _isThinking = true; // Activar estado pensando
    });

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

    // Usar IA para procesamiento inteligente (modo único - más natural)
    final stepName = _currentStep.toString().split('.').last;

    // Procesar respuesta con IA
    final processedData = await ConversationalAIService.processUserResponse(
      userResponse: userResponse,
      conversationStep: stepName,
      userName: _userName ?? '', // Puede ser vacío en el paso awakening
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
    final hasError = processedData['error'] as bool? ?? false;

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

    if (displayValue != null && processedValue != null) {
      // NUEVO: Guardar en estado pendiente para validación, NO guardar directamente
      _pendingValidationValue = processedValue;
      _isWaitingForConfirmation = true;

      // VALIDACIÓN SIEMPRE OBLIGATORIA: Confirmar TODOS los datos
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
        break;
      case OnboardingStep.askingAiName:
        _aiName = extractedValue;
        _collectedData['aiName'] = extractedValue;
        // Actualizar nombre de la IA en los subtítulos
        _subtitleController.updateNames(aiName: extractedValue);
        break;
      case OnboardingStep.askingMeetStory:
        _meetStory = extractedValue;
        _collectedData['meetStory'] = extractedValue;
        break;
      default:
        break;
    }
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
        userName: _userName ?? '',
        userLastResponse: '',
        conversationStep: stepName,
        aiName: _aiName,
        aiCountryCode: _aiCountry,
        collectedData: _collectedData,
      );
    } catch (e) {
      Log.e('Error generando pregunta con IA: $e');
      await _retryCurrentStep();
      return;
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

  Future<void> _finishOnboarding() async {
    // ✅ VALIDACIÓN CRÍTICA: Todos los datos deben estar presentes
    if (_userName == null ||
        _userName!.isEmpty ||
        _aiName == null ||
        _aiName!.isEmpty ||
        _userBirthday == null ||
        _meetStory == null ||
        _meetStory!.isEmpty ||
        _userCountry == null ||
        _userCountry!.isEmpty ||
        _aiCountry == null ||
        _aiCountry!.isEmpty) {
      Log.e('❌ DATOS INCOMPLETOS - no se puede completar onboarding');
      await _retryCurrentStep();
      return;
    }

    // ✅ TODOS LOS DATOS VALIDADOS - Proceder con el onboarding
    Log.d('✅ DATOS COMPLETOS - Finalizando onboarding', tag: 'CONV_ONBOARDING');

    await widget.onFinish(
      userName: _userName!,
      aiName: _aiName!,
      userBirthday: _userBirthday!,
      meetStory: _meetStory!,
      userCountryCode: _userCountry!,
      aiCountryCode: _aiCountry!,
    );
  }

  Future<String?> _showTextInputDialog(OnboardingStep step) async {
    // No mostrar teclado si estamos hablando
    if (_isSpeaking || _isTtsPlaying) {
      return null;
    }

    // Pausar cualquier TTS activo
    if (_isTtsPlaying) {
      await _openaiTtsService.stop();
      setState(() => _isTtsPlaying = false);
    }

    // Mensaje contextual según el paso
    String hintText = 'Escribe tu respuesta aquí...';
    String titleText = 'Respuesta por texto';

    switch (step) {
      case OnboardingStep.awakening:
        hintText = 'Escribe tu nombre...';
        titleText = '¿Cómo te llamas?';
        break;
      case OnboardingStep.askingCountry:
        hintText = 'Escribe tu país...';
        titleText = '¿De dónde eres?';
        break;
      case OnboardingStep.askingBirthday:
        hintText = 'Escribe tu fecha de nacimiento (DD/MM/AAAA)...';
        titleText = '¿Cuándo naciste?';
        break;
      case OnboardingStep.askingAiCountry:
        hintText = 'Escribe el país para la IA...';
        titleText = '¿De dónde quieres que sea?';
        break;
      case OnboardingStep.askingAiName:
        hintText = 'Escribe el nombre para la IA...';
        titleText = '¿Cómo quieres que me llame?';
        break;
      case OnboardingStep.askingMeetStory:
        hintText = 'Escribe cómo nos conocimos...';
        titleText = '¿Cómo nos conocimos?';
        break;
      default:
        break;
    }

    final textController = TextEditingController();

    if (!mounted) return null;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00FFD4), width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF001122), Colors.black],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Título
              Text(
                titleText,
                style: const TextStyle(
                  color: Color(0xFF00FFD4),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Campo de texto
              TextField(
                controller: textController,
                autofocus: true,
                maxLines: step == OnboardingStep.askingMeetStory ? 4 : 1,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00FFD4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF00FFD4),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.black54,
                ),
              ),
              const SizedBox(height: 24),

              // Botones
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón Cancelar
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),

                  // Botón Enviar
                  ElevatedButton(
                    onPressed: () {
                      final text = textController.text.trim();
                      Navigator.of(context).pop(text.isNotEmpty ? text : null);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FFD4),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Enviar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return result;
  }

  @override
  void dispose() {
    _speechTimeoutTimer?.cancel();
    _pulseController.dispose();
    _hybridSttService.dispose();
    _audioPlayer.dispose();
    _openaiTtsService.dispose();
    _subtitleController.dispose();
    _progressiveSubtitleController.dispose();
    super.dispose();
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
