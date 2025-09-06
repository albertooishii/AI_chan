import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/onboarding/application/controllers/onboarding_lifecycle_controller.dart';
import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';
import 'package:ai_chan/onboarding/services/conversational_onboarding_service.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/services/openai_tts_service.dart';
import 'package:ai_chan/shared/services/hybrid_stt_service.dart';
import 'package:ai_chan/shared/controllers/audio_subtitle_controller.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/widgets/conversational_subtitles.dart';
import 'package:ai_chan/shared/widgets/country_autocomplete.dart';
import 'package:ai_chan/shared/widgets/female_name_autocomplete.dart';
import 'package:ai_chan/onboarding/presentation/widgets/birth_date_field.dart';
import 'package:ai_chan/shared/constants/countries_es.dart';
import 'dart:async';
import 'onboarding_screen.dart' show OnboardingFinishCallback, OnboardingScreen;

/// Pantalla de onboarding completamente conversacional
/// Implementa el flujo tipo "despertar" donde AI-chan habla con el usuario
class ConversationalOnboardingScreen extends StatefulWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final OnboardingLifecycleController? onboardingLifecycle;

  const ConversationalOnboardingScreen({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onboardingLifecycle,
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
  OnboardingStep _currentStep = OnboardingStep.askingName;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isTtsPlaying = false;
  bool _isThinking = false;
  // Marca si estamos en la reproducción del primer mensaje inicial; permite
  // habilitar el botón de texto automáticamente cuando termine.
  bool _isDuringInitialIntro = false;
  Timer? _speechTimeoutTimer; // Para controlar manualmente el timeout

  // Control de operaciones asíncronas para evitar interferencias
  int _currentOperationId = 0;

  // Sistema de reintentos para errores de TTS
  int _ttsRetryCount = 0;
  static const int _maxTtsRetries = 3;

  // Control de interacción del usuario
  bool _hasUserResponded =
      false; // Para habilitar botón de corregir después de primera respuesta
  // Variables para manejar el estado del onboarding
  bool _isDialogOpen = false; // Para prevenir diálogos múltiples simultáneos

  // Suscripción y timer para subtítulos progresivos - mantenemos referencias
  // para poder cancelarlos cuando iniciemos una nueva reproducción
  StreamSubscription<String>? _progressiveSub;
  Timer? _progressiveTimer;

  // Datos recolectados con procesamiento inteligente
  String? _userName;
  String? _userCountry;
  DateTime? _userBirthdate;
  String? _aiName;
  String? _aiCountry;
  String? _meetStory;

  // Datos dinámicos para IA (siempre habilitado - modo más natural)
  final Map<String, dynamic> _collectedData = {};

  // Nueva clase de memoria para el enfoque flexible
  MemoryData _currentMemory = const MemoryData();

  // Almacenar la última respuesta del usuario para contexto
  String _lastUserResponse = '';

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _startOnboardingFlow();
  }

  /// Sincroniza _currentMemory con las variables individuales
  void _syncMemoryFromIndividualFields() {
    _currentMemory = _currentMemory.copyWith(
      userName: _userName,
      userCountry: _userCountry,
      userBirthdate: _userBirthdate?.toIso8601String(),
      aiCountry: _aiCountry,
      aiName: _aiName,
      meetStory: _meetStory,
    );
  }

  /// Sincroniza las variables individuales con _currentMemory
  void _syncIndividualFieldsFromMemory() {
    _userName = _currentMemory.userName;
    _userCountry = _currentMemory.userCountry;
    _userBirthdate = _currentMemory.userBirthdate != null
        ? DateTime.tryParse(_currentMemory.userBirthdate!)
        : null;
    _aiCountry = _currentMemory.aiCountry;
    _aiName = _currentMemory.aiName;
    _meetStory = _currentMemory.meetStory;
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
          _safeSetState(() => _isListening = false);
        }
      },
      onError: (error) {
        Log.e('STT Error: $error', tag: 'CONV_ONBOARDING');
        _safeSetState(() => _isListening = false);
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

  /// Helper para setState seguro que verifica si el widget está montado
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  /// Verifica si el usuario ya ha proporcionado algún dato
  /// para determinar si el botón de corregir debe estar habilitado
  /// Prompt contextual para STT que ayuda a OpenAI Whisper a entender mejor
  /// los nombres, países y términos comunes durante el onboarding
  /// TEMPORALMENTE DESHABILITADO: Causa prompt leakage en OpenAI Whisper
  // static const String _onboardingSTTPrompt =
  //     'Esta es una conversación de onboarding en español. El usuario puede mencionar nombres propios como Alberto, Antonio, María, Carmen, José, Ana, etc. '
  //     'También países como España, México, Argentina, Colombia, Perú, Chile, Venezuela, Ecuador, Uruguay, Paraguay, etc. '
  //     'Puede mencionar fechas de nacimiento con formato día/mes/año como "15 de marzo de 1990" o "3/4/1985". '
  //     'El usuario también puede dar nombres creativos para una IA como AI-chan, Luna, Sofia, Aria, Nova, etc. '
  //     'Transcribe con precisión nombres propios, países hispanohablantes y fechas.';

  /// Determina la configuración de voz con acento dinámico
  Map<String, dynamic> _getVoiceConfiguration() {
    final String instructions =
        ConversationalOnboardingService.getVoiceInstructions(
          userCountry: _userCountry,
          aiCountry: _aiCountry,
        );

    return {
      'voice': 'marin',
      'languageCode': 'es-ES',
      'provider': 'openai',
      'speed': 1.0,
      'instructions': instructions,
    };
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
                              onboardingLifecycle: widget.onboardingLifecycle,
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
                              size: 18,
                            ),
                            label: Text(
                              _isListening ? 'Parar Mic' : 'Activar Mic',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isListening
                                  ? Colors.red.withValues(alpha: 0.2)
                                  : AppColors.secondary.withValues(alpha: 0.2),
                              foregroundColor: _isListening
                                  ? Colors.red
                                  : AppColors.secondary,
                              minimumSize: const Size(0, 56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Botón para modo texto (deshabilitado solo durante primer mensaje de IA)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _hasUserResponded
                                ? () async {
                                    // 🚨 CANCELAR INMEDIATAMENTE CUALQUIER OPERACIÓN EN CURSO
                                    ++_currentOperationId;
                                    Log.d(
                                      '🔄 BOTÓN CORREGIR - Incrementando operación a #$_currentOperationId',
                                      tag: 'CONV_ONBOARDING',
                                    );

                                    // 🛑 DETENER AUDIO SIEMPRE (sin importar el estado)
                                    Log.d(
                                      '🛑 BOTÓN CORREGIR - Deteniendo audio...',
                                      tag: 'CONV_ONBOARDING',
                                    );
                                    await _openaiTtsService.stop();

                                    // 🚨 DETENCIÓN DE EMERGENCIA - También detener AudioPlayer directamente
                                    try {
                                      await _audioPlayer.stop();
                                      Log.d(
                                        '🛑 EMERGENCIA - AudioPlayer también detenido',
                                        tag: 'CONV_ONBOARDING',
                                      );
                                    } catch (e) {
                                      Log.d(
                                        '⚠️ AudioPlayer ya estaba detenido: $e',
                                        tag: 'CONV_ONBOARDING',
                                      );
                                    }

                                    // 🚨 DETENCIÓN GLOBAL - Detener servicio de audio global
                                    try {
                                      final globalAudio = di.getAudioPlayback();
                                      await globalAudio.stop();
                                      Log.d(
                                        '🛑 EMERGENCIA - Audio global también detenido',
                                        tag: 'CONV_ONBOARDING',
                                      );
                                    } catch (e) {
                                      Log.d(
                                        '⚠️ Audio global ya estaba detenido: $e',
                                        tag: 'CONV_ONBOARDING',
                                      );
                                    }

                                    Log.d(
                                      '✅ BOTÓN CORREGIR - Audio detenido',
                                      tag: 'CONV_ONBOARDING',
                                    );

                                    // Detener micrófono si está activo
                                    if (_isListening) {
                                      await _stopListening();
                                    }

                                    // 🚨 RESETEAR TODOS LOS ESTADOS
                                    setState(() {
                                      _isSpeaking = false;
                                      _isListening = false;
                                      _isThinking = false;
                                      // Asegurar que la marca de TTS también se limpie para
                                      // permitir abrir el diálogo de texto inmediatamente
                                      _isTtsPlaying = false;
                                    });

                                    Log.d(
                                      '🎛️ BOTÓN CORREGIR - Estados reseteados',
                                      tag: 'CONV_ONBOARDING',
                                    );

                                    // Mostrar dialogo de texto
                                    final result = await _showTextInputDialog(
                                      _currentStep,
                                    );
                                    if (result != null && result.isNotEmpty) {
                                      await _processUserResponse(
                                        result,
                                        fromTextInput: true,
                                      );
                                    } else {
                                      // No es necesario reactivar nada ya que el botón siempre está habilitado
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.keyboard, size: 18),
                            label: Text(
                              (_isThinking || _isSpeaking)
                                  ? 'Corregir respuesta'
                                  : 'Escribir respuesta',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !_hasUserResponded
                                  ? Colors.grey.withValues(alpha: 0.2)
                                  : (_isThinking || _isSpeaking)
                                  ? AppColors.cyberpunkYellow.withValues(
                                      alpha: 0.2,
                                    )
                                  : AppColors.primary.withValues(alpha: 0.2),
                              foregroundColor: !_hasUserResponded
                                  ? Colors.grey
                                  : (_isThinking || _isSpeaking)
                                  ? AppColors.cyberpunkYellow
                                  : AppColors.primary,
                              minimumSize: const Size(0, 56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
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

    // � CAPTURAR ID DE OPERACIÓN ACTUAL PARA VERIFICAR CANCELACIONES
    final currentOperationId = _currentOperationId;

    // �🚨 VALIDACIÓN CRÍTICA: Detectar texto vacío y reintentar automáticamente
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

        await _speakAndWaitForResponse(
          ConversationalOnboardingService.systemErrorFallback,
        );
        return;
      }
    }

    // 🔒 VERIFICAR SI ESTA OPERACIÓN FUE CANCELADA ANTES DE CONTINUAR
    if (currentOperationId != _currentOperationId) {
      Log.d(
        '🛑 Audio cancelado antes de reproducir (operación #$currentOperationId vs actual #$_currentOperationId) - texto: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
        tag: 'CONV_ONBOARDING',
      );
      // 🚨 RESETEAR ESTADO AL CANCELAR
      _safeSetState(() {
        _isThinking = false;
        _isSpeaking = false;
      });
      return;
    }

    // Reset contador cuando el texto es válido
    _ttsRetryCount = 0;

    _safeSetState(() {
      _isSpeaking = true;
      _isTtsPlaying = true; // Marcar que TTS está reproduciéndose
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

      // 🔒 VERIFICAR CANCELACIÓN ANTES DE INICIAR TTS
      if (currentOperationId != _currentOperationId) {
        Log.d(
          '🛑 Operación cancelada antes de iniciar TTS',
          tag: 'CONV_ONBOARDING',
        );
        return;
      }

      final audioInfo = await _openaiTtsService.synthesizeAndPlay(
        text,
        options: voiceConfig,
      );

      // 🔒 VERIFICAR CANCELACIÓN DESPUÉS DE SÍNTESIS
      if (currentOperationId != _currentOperationId) {
        Log.d(
          '🛑 Operación cancelada después de síntesis, deteniendo audio',
          tag: 'CONV_ONBOARDING',
        );
        await _openaiTtsService.stop();
        return;
      }

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
        // Antes de suscribirnos, cancelar cualquier reproducción/subs previa
        _progressiveSub?.cancel();
        _progressiveTimer?.cancel();
        _progressiveSub = _progressiveSubtitleController.progressiveTextStream
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

        _progressiveTimer?.cancel();
        _progressiveTimer = Timer.periodic(updateInterval, (timer) {
          // 🔒 VERIFICAR CANCELACIÓN DURANTE REPRODUCCIÓN
          if (!mounted ||
              !_isSpeaking ||
              currentOperationId != _currentOperationId) {
            Log.d(
              '🛑 Subtítulos cancelados durante reproducción',
              tag: 'CONV_ONBOARDING',
            );
            timer.cancel();
            _progressiveTimer?.cancel();
            _progressiveTimer = null;
            _progressiveSub?.cancel();
            _progressiveSub = null;
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
            _progressiveTimer?.cancel();
            _progressiveTimer = null;
            _progressiveSub?.cancel();
            _progressiveSub = null;
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

        // 🔒 VERIFICAR CANCELACIÓN DESPUÉS DE REPRODUCCIÓN
        if (currentOperationId != _currentOperationId) {
          Log.d(
            '🛑 Audio completado pero operación fue cancelada',
            tag: 'CONV_ONBOARDING',
          );
          _progressiveTimer?.cancel();
          _progressiveTimer = null;
          _progressiveSub?.cancel();
          _progressiveSub = null;
          return;
        }

        // Limpiar suscripción si aún está activa
        _progressiveTimer?.cancel();
        _progressiveTimer = null;
        _progressiveSub?.cancel();
        _progressiveSub = null;

        Log.d(
          '✅ OpenAI TTS con subtítulos progresivos completado exitosamente',
          tag: 'CONV_ONBOARDING',
        );

        // 🔍 LOG DETALLADO: Estado después de completar TTS
        Log.d('📊 ESTADO POST-TTS:', tag: 'CONV_ONBOARDING');
        Log.d('   - _isTtsPlaying: $_isTtsPlaying', tag: 'CONV_ONBOARDING');
        Log.d('   - _isSpeaking: $_isSpeaking', tag: 'CONV_ONBOARDING');
        Log.d(
          '   - OpenAI TTS isPlaying: ${_openaiTtsService.isPlaying}',
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

      // 🔒 VERIFICAR CANCELACIÓN EN CASO DE ERROR
      if (currentOperationId != _currentOperationId) {
        Log.d('🛑 Operación cancelada durante error', tag: 'CONV_ONBOARDING');
        return;
      }

      // En caso de error, mostrar texto completo inmediatamente
      _subtitleController.handleAiChunk(
        text,
        audioStarted: true,
        suppressFurther: false,
      );
    }

    if (!mounted) return;

    // 🔒 VERIFICAR CANCELACIÓN ANTES DE FINALIZAR
    if (currentOperationId != _currentOperationId) {
      Log.d(
        '🛑 Operación cancelada al final de _speakAndWaitForResponse',
        tag: 'CONV_ONBOARDING',
      );
      return;
    }

    _safeSetState(() {
      _isSpeaking = false;
      _isTtsPlaying = false; // Marcar que TTS terminó
      _isThinking = false; // Asegurar que pensando esté desactivado
    });

    // 🔍 LOG DESPUÉS DE ACTUALIZAR ESTADO
    Log.d('🔄 ESTADO ACTUALIZADO DESPUÉS DE TTS:', tag: 'CONV_ONBOARDING');
    Log.d('   - _isTtsPlaying: $_isTtsPlaying', tag: 'CONV_ONBOARDING');
    Log.d('   - _isSpeaking: $_isSpeaking', tag: 'CONV_ONBOARDING');
    Log.d('   - _isThinking: $_isThinking', tag: 'CONV_ONBOARDING');

    // Si estábamos reproduciendo el primer mensaje introductorio, considerar
    // que el usuario ya puede interactuar por texto inmediatamente.
    if (_isDuringInitialIntro) {
      _safeSetState(() {
        _hasUserResponded = true; // habilitar botón de texto
        _isDuringInitialIntro = false;
      });
    }

    // Reducir delay para respuesta más fluida
    await Future.delayed(const Duration(milliseconds: 300));

    // 🔒 VERIFICAR CANCELACIÓN ANTES DE ACTIVAR MICRÓFONO
    if (currentOperationId != _currentOperationId) {
      Log.d(
        '🛑 No activar micrófono - operación cancelada',
        tag: 'CONV_ONBOARDING',
      );
      return;
    }

    // 🔍 LOG DETALLADO: Estado antes de activar micrófono
    Log.d(
      '🎙️ A PUNTO DE ACTIVAR MICRÓFONO - Estado actual:',
      tag: 'CONV_ONBOARDING',
    );
    Log.d('   - _isTtsPlaying: $_isTtsPlaying', tag: 'CONV_ONBOARDING');
    Log.d('   - _isSpeaking: $_isSpeaking', tag: 'CONV_ONBOARDING');
    Log.d(
      '   - OpenAI TTS isPlaying: ${_openaiTtsService.isPlaying}',
      tag: 'CONV_ONBOARDING',
    );

    _startListening();
  }

  Future<void> _startOnboardingFlow() async {
    await Future.delayed(const Duration(milliseconds: 1500)); // Pausa dramática

    // 🚀 LOG: Inicio del flujo conversacional
    Log.d(
      '🚀 INICIANDO ONBOARDING CONVERSACIONAL - PRIMER MENSAJE',
      tag: 'CONV_ONBOARDING',
    );

    // Limpiar historial de conversación para empezar desde cero
    ConversationalOnboardingService.clearConversationHistory();

    // Mensaje inicial - usar la constante única definida en el servicio
    // Marcar que estamos en la intro inicial para bloquear el botón de texto
    // sólo durante esta reproducción.
    _safeSetState(() => _isDuringInitialIntro = true);
    await _speakAndWaitForResponse(
      ConversationalOnboardingService.initialMessage,
    );
  }

  Future<void> _retryCurrentStep() async {
    final currentOperationId = ++_currentOperationId;
    Log.i('🔄 Reintentando paso actual (Operation #$currentOperationId)');

    // Reintenta el paso actual usando IA para generar mensaje de reintento

    String retryMessage;
    try {
      // Sincronizar memoria antes de llamar al servicio
      _syncMemoryFromIndividualFields();

      retryMessage = await ConversationalOnboardingService.generateNextResponse(
        currentMemory: _currentMemory,
        userLastResponse: 'No entendí',
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

    // 🔍 LOG DETALLADO: Verificar estado antes de activar micrófono
    Log.d(
      '🎙️ VERIFICANDO ESTADO ANTES DE ACTIVAR MICRÓFONO:',
      tag: 'CONV_ONBOARDING',
    );
    Log.d('   - _isTtsPlaying: $_isTtsPlaying', tag: 'CONV_ONBOARDING');
    Log.d('   - _isSpeaking: $_isSpeaking', tag: 'CONV_ONBOARDING');
    Log.d(
      '   - OpenAI TTS isPlaying: ${_openaiTtsService.isPlaying}',
      tag: 'CONV_ONBOARDING',
    );
    Log.d(
      '   - AudioPlayer state: ${_audioPlayer.state}',
      tag: 'CONV_ONBOARDING',
    );

    // 🚨 VERIFICAR SI EL AUDIO ESTÁ REPRODUCIÉNDOSE
    if (_isTtsPlaying || _isSpeaking || _openaiTtsService.isPlaying) {
      Log.e(
        '🚨 PROBLEMA DETECTADO: Intentando activar micrófono mientras audio aún reproduce!',
        tag: 'CONV_ONBOARDING',
      );
      Log.e(
        '   - Esto causará que el micrófono capture el audio TTS',
        tag: 'CONV_ONBOARDING',
      );
      Log.e('   - CANCELANDO activación de micrófono', tag: 'CONV_ONBOARDING');
      return;
    }

    Log.d(
      '✅ Estado OK - Activando micrófono de forma segura',
      tag: 'CONV_ONBOARDING',
    );

    _safeSetState(() {
      _isListening = true;
    });

    // Cancelar timer anterior si existe
    _speechTimeoutTimer?.cancel();

    await _hybridSttService.listen(
      onResult: (text) {
        _safeSetState(() {
          Log.d('🗣️ Usuario dice: "$text"', tag: 'CONV_ONBOARDING');
        });

        // Mostrar subtítulo en tiempo real del usuario
        if (text.isNotEmpty) {
          _subtitleController.handleUserTranscription(text);
        }

        // Procesar resultado final (el híbrido ya maneja finalizaciones)
        _processUserResponse(text);
      },
      // TEMPORALMENTE DESHABILITADO: contextPrompt causa prompt leakage en OpenAI Whisper
      // contextPrompt: _onboardingSTTPrompt, // 🎯 Añadir contexto para onboarding
    );
  }

  Future<void> _stopListening() async {
    _speechTimeoutTimer?.cancel(); // Limpiar timer
    if (_hybridSttService.isListening) {
      await _hybridSttService.stop();
      _safeSetState(() {
        _isListening = false;
      });
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

    // Marcar que el usuario ya ha respondido (habilita botón de corregir)
    if (!_hasUserResponded) {
      _safeSetState(() {
        _hasUserResponded = true;
      });
    }

    // 🚨 DETENER INMEDIATAMENTE CUALQUIER AUDIO EN REPRODUCCIÓN
    if (_isSpeaking) {
      Log.d(
        '🛑 Deteniendo audio en reproducción por nueva entrada del usuario',
        tag: 'CONV_ONBOARDING',
      );
      await _openaiTtsService.stop();
    }

    // Detener micrófono si está activo
    if (_isListening) {
      await _stopListening();
    }

    // Guardar la última respuesta del usuario para contexto
    _lastUserResponse = userResponse;

    // 🔄 Generar nuevo ID de operación para cancelar operaciones anteriores
    final currentOperationId = ++_currentOperationId;

    // 🚨 FORZAR ESTADO LIMPIO después de cancelación
    _safeSetState(() {
      _isListening = false;
      _isSpeaking = false;
      _isTtsPlaying = false;
      _isThinking = true; // Activar estado pensando
    });

    // Reset contador de reintentos al procesar nueva respuesta del usuario
    _ttsRetryCount = 0;

    // 🟢 LOG: Respuesta del usuario
    Log.d(
      '🎤 USUARIO DIJO: "$userResponse" (operación #$currentOperationId)',
      tag: 'CONV_ONBOARDING',
    );

    // Actualizar subtítulo del usuario
    _subtitleController.handleUserTranscription(userResponse);

    // Usar IA para procesamiento inteligente (modo único - más natural)

    // Procesar respuesta con IA
    _syncMemoryFromIndividualFields();
    final processedResult =
        await ConversationalOnboardingService.processUserResponse(
          currentMemory: _currentMemory,
          userResponse: userResponse,
        );

    // 🔒 Verificar si esta operación fue cancelada por una nueva
    if (currentOperationId != _currentOperationId) {
      Log.d(
        '🔄 Operación #$currentOperationId cancelada, ignorando resultado',
        tag: 'CONV_ONBOARDING',
      );
      _safeSetState(
        () => _isThinking = false,
      ); // Desactivar pensando si se cancela
      return;
    }

    // Si estamos en finalMessage, cualquier respuesta nos lleva a completion
    if (_currentStep == OnboardingStep.finalMessage) {
      _goToNextStep(); // Ir a completion
      await _finishOnboarding();
      return;
    }
    // Extraer información del resultado
    final updatedMemory = processedResult['updatedMemory'] as MemoryData;
    final extractedData =
        processedResult['extractedData'] as Map<String, dynamic>?;
    final aiResponse = processedResult['aiResponse'] as String?;
    final hasError = processedResult['error'] as bool? ?? false;

    // Actualizar la memoria local con los nuevos datos
    _currentMemory = updatedMemory;
    _syncIndividualFieldsFromMemory();

    // Si la IA extrajo un valor, usarlo como processedValue para compatibilidad
    final processedValue = extractedData?['value'] as String?;
    final extractedDataType = extractedData?['type'] as String?;

    // Ahora el servicio maneja directamente CONFIRM_GENERATED_STORY, no necesitamos lógica especial aquí

    // Si la IA no devolvió processedValue explícito, considerar que no lo entendió
    // y pedir repetición/esclarecimiento específico del paso actual.
    if (processedValue == null || processedValue.trim().isEmpty) {
      Log.w(
        '⚠️ processedValue nulo o vacío para paso $_currentStep — forzando reintento',
        tag: 'CONV_ONBOARDING',
      );
      _safeSetState(() => _isThinking = false);

      // Usar mensaje de reintento específico por paso para pedir que repita
      final retryMessage = _getRetryMessageForStep(_currentStep);
      await _speakAndWaitForResponse(retryMessage);
      return;
    }

    // 🚨 Manejar errores de conexión/servidor - quedarse en el mismo paso
    if (hasError) {
      Log.d(
        '🚨 ERROR DETECTADO - quedándose en el paso actual para reintento',
        tag: 'CONV_ONBOARDING',
      );
      _safeSetState(() => _isThinking = false);

      // Usar un mensaje de reintento claro y específico por paso en lugar de depender
      // de aiResponse, que a veces contiene preguntas inapropiadas o confusas.
      final retryMessage = _getRetryMessageForStep(_currentStep);
      await _speakAndWaitForResponse(retryMessage);
      return;
    }

    // ✅ NUEVO FLUJO SIN CONFIRMACIONES: Intentar guardar dato y continuar solo si es exitoso
    Log.d('⚡ INTENTANDO GUARDAR: $processedValue', tag: 'CONV_ONBOARDING');

    // El servicio ya maneja AUTO_GENERATE_STORY y CONFIRM_GENERATED_STORY automáticamente
    // No necesitamos lógica especial aquí

    // Intentar guardar el valor - solo continúa si fue exitoso
    // 🔧 USAR EL TIPO DE DATO DETECTADO POR LA IA, NO EL PASO ACTUAL
    final bool dataSaved = _updateDataFromExtraction(
      extractedDataType,
      processedValue,
    );

    if (dataSaved) {
      Log.d(
        '✅ DATO GUARDADO EXITOSAMENTE: $processedValue',
        tag: 'CONV_ONBOARDING',
      );

      // Avanzar al siguiente paso ANTES de la respuesta de la IA
      _goToNextStep();

      // La IA reacciona al dato Y hace la siguiente pregunta en una sola respuesta
      if (aiResponse != null) {
        _safeSetState(() => _isThinking = false);
        await _speakAndWaitForResponse(aiResponse);

        // 🔒 CRÍTICO: NO continuar hasta que el audio termine COMPLETAMENTE
        // El micrófono se activa automáticamente al final de _speakAndWaitForResponse
        return; // Salir aquí para evitar activación prematura del micrófono
      }

      // Solo continuar con triggerStepQuestion si no hubo aiResponse
      if (_currentStep != OnboardingStep.completion) {
        await _triggerStepQuestion(userLastResponse: _lastUserResponse);
      } else {
        await _finishOnboarding();
      }
    } else {
      Log.w(
        '❌ DATO RECHAZADO - reintentando paso actual: $processedValue',
        tag: 'CONV_ONBOARDING',
      );

      // Evitar usar aiResponse aquí porque puede contener la siguiente pregunta
      // (p. ej. la IA puede avanzar al siguiente paso aunque el dato fue rechazado).
      // En su lugar, pedir clarificación específica del paso actual.
      _safeSetState(() => _isThinking = false);
      final retryMessage = _getRetryMessageForStep(_currentStep);
      await _speakAndWaitForResponse(retryMessage);
      return;
    }

    // Si no se extrajo ningún valor válido, pedir repetición específica del paso
    // para evitar que la IA avance el flujo o pregunte por datos de la IA.
    final retryMessage = _getRetryMessageForStep(_currentStep);
    Log.d(
      '📝 No se extrajo valor, usando mensaje de reintento para el paso $_currentStep',
      tag: 'CONV_ONBOARDING',
    );
    await _speakAndWaitForResponse(retryMessage);
    return;
  }

  bool _updateDataFromExtraction(String? dataType, String extractedValue) {
    // Si no se detectó tipo de dato, usar el paso actual como fallback
    final String effectiveDataType =
        dataType ?? _currentStep.toString().split('.').last;

    // Usar el service para validar los datos
    final validationResult =
        ConversationalOnboardingService.validateAndSaveData(
          effectiveDataType,
          extractedValue,
        );
    final isValid = validationResult['isValid'] as bool;
    final processedValue = validationResult['processedValue'] as String?;
    final reason = validationResult['reason'] as String?;

    if (!isValid) {
      Log.w(
        '$effectiveDataType: Dato rechazado - ${reason ?? "Razón desconocida"}',
        tag: 'CONV_ONBOARDING',
      );
      // Mantener el paso actual sin avanzar
      return false;
    }

    // Datos válidos - guardar según el tipo de dato detectado por la IA
    switch (effectiveDataType) {
      case 'userName':
        _userName = processedValue!;
        _collectedData['userName'] = processedValue;
        // Actualizar nombre del usuario en los subtítulos
        _subtitleController.updateNames(userName: processedValue);
        Log.d(
          'userName: Nombre guardado: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      case 'userCountry':
        _userCountry = processedValue!;
        _collectedData['userCountry'] = processedValue;
        Log.d(
          'userCountry: País confirmado y guardado: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      case 'userBirthdate':
        // Si hay fecha parseada, usarla; si no, intentar parsear del valor original
        final parsedDate = validationResult['parsedDate'] as DateTime?;
        if (parsedDate != null) {
          _userBirthdate = parsedDate;
        } else {
          // Fallback: intentar parsear manualmente
          try {
            final parts = processedValue!.split('/');
            if (parts.length == 3) {
              _userBirthdate = DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              );
            }
          } catch (e) {
            Log.w(
              'Error parseando fecha en fallback: $e',
              tag: 'CONV_ONBOARDING',
            );
            return false;
          }
        }
        _collectedData['userBirthdate'] = _userBirthdate?.toIso8601String();
        Log.d(
          'userBirthdate: Fecha de nacimiento confirmada y guardada: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      case 'aiCountry':
        _aiCountry = processedValue!;
        _collectedData['aiCountry'] = processedValue;
        Log.d(
          'aiCountry: País de la IA confirmado y guardado: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      case 'aiName':
        _aiName = processedValue!;
        _collectedData['aiName'] = processedValue;
        // Actualizar nombre de la IA en los subtítulos
        _subtitleController.updateNames(aiName: processedValue);
        Log.d(
          'aiName: Nombre de la IA confirmado y guardado: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      case 'meetStory':
        _meetStory = processedValue!;
        _collectedData['meetStory'] = processedValue;
        Log.d(
          'meetStory: Historia de encuentro confirmada y guardada: $processedValue',
          tag: 'CONV_ONBOARDING',
        );
        break;
      // Fallback para compatibilidad con OnboardingStep
      case 'askingName':
        return _updateDataFromExtraction('userName', extractedValue);
      case 'askingCountry':
        return _updateDataFromExtraction('userCountry', extractedValue);
      case 'askingBirthdate':
        return _updateDataFromExtraction('userBirthdate', extractedValue);
      case 'askingAiCountry':
        return _updateDataFromExtraction('aiCountry', extractedValue);
      case 'askingAiName':
        return _updateDataFromExtraction('aiName', extractedValue);
      case 'askingMeetStory':
        return _updateDataFromExtraction('meetStory', extractedValue);
      default:
        Log.w(
          'Tipo de dato no manejado: $effectiveDataType',
          tag: 'CONV_ONBOARDING',
        );
        return false;
    }

    return true;
  }

  void _goToNextStep() {
    // En lugar de seguir una secuencia rígida, determinar inteligentemente
    // qué paso es necesario basándose en los datos que faltan
    final missingData = _currentMemory.getMissingData();

    if (missingData.isEmpty) {
      // Todos los datos están completos, ir a finalización
      _safeSetState(() {
        _currentStep = OnboardingStep.finalMessage;
      });
      return;
    }

    // Determinar el siguiente paso basándose en el primer dato faltante
    final nextDataType = missingData.first;
    OnboardingStep targetStep;

    switch (nextDataType) {
      case 'userName':
        targetStep = OnboardingStep.askingName;
        break;
      case 'userCountry':
        targetStep = OnboardingStep.askingCountry;
        break;
      case 'userBirthdate':
        targetStep = OnboardingStep.askingBirthdate;
        break;
      case 'aiCountry':
        targetStep = OnboardingStep.askingAiCountry;
        break;
      case 'aiName':
        targetStep = OnboardingStep.askingAiName;
        break;
      case 'meetStory':
        targetStep = OnboardingStep.askingMeetStory;
        break;
      default:
        // Fallback a la lógica secuencial anterior
        final int currentIndex = _currentStep.index;
        if (currentIndex < OnboardingStep.values.length - 1) {
          targetStep = OnboardingStep.values[currentIndex + 1];
        } else {
          targetStep = OnboardingStep.completion;
        }
    }

    _safeSetState(() {
      _currentStep = targetStep;
    });

    if (_currentStep == OnboardingStep.completion) {
      _finishOnboarding();
    }
  }

  Future<void> _triggerStepQuestion({String? userLastResponse}) async {
    // Generar la pregunta del paso actual usando la IA
    String stepQuestion;

    if (_currentStep == OnboardingStep.completion) {
      await _finishOnboarding();
      return;
    }

    try {
      // Sincronizar memoria antes de generar siguiente pregunta
      _syncMemoryFromIndividualFields();

      // Generar pregunta dinámica usando el servicio de IA conversacional
      stepQuestion = await ConversationalOnboardingService.generateNextResponse(
        currentMemory: _currentMemory,
        userLastResponse: userLastResponse ?? _lastUserResponse,
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
      stepQuestion = ConversationalOnboardingService.systemErrorAskForHelp;
    }

    await _speakAndWaitForResponse(stepQuestion);
  }

  /// Devuelve un mensaje de reintento específico por paso cuando no se entendió el dato
  String _getRetryMessageForStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.askingName:
        return 'Disculpa, no escuché bien tu nombre. ¿Podrías decírmelo de nuevo, por favor?';
      case OnboardingStep.askingCountry:
        return 'Perdona, no oí bien tu país. ¿De qué país decías que eras exactamente?';
      case OnboardingStep.askingBirthdate:
        return 'No he entendido bien la fecha. ¿Podrías decirme tu fecha de nacimiento completa? Con el año incluído.';
      case OnboardingStep.askingAiCountry:
        return 'No logro recordar mi país... ¿puedes ayudarme? ¿De qué país era yo?';
      case OnboardingStep.askingAiName:
        return 'Perdona, mi nombre... no consigo recordarlo. ¿Cómo me llamaba yo?';
      case OnboardingStep.askingMeetStory:
        return 'No he entendido la historia... estoy intentando recordar pero no soy capaz. ¿Puedes recordarme cómo nos conocimos?';
      case OnboardingStep.finalMessage:
      case OnboardingStep.completion:
        return 'Perdona, no he entendido. ¿Puedes repetirlo, por favor?';
    }
  }

  Future<void> _finishOnboarding() async {
    // ✅ Sincronizar memoria final
    _syncMemoryFromIndividualFields();

    // ✅ Si todos los datos están disponibles, completar onboarding
    if (_currentMemory.isComplete() && _userBirthdate != null) {
      Log.d(
        '✅ DATOS COMPLETOS - Finalizando onboarding',
        tag: 'CONV_ONBOARDING',
      );

      await widget.onFinish(
        userName: _currentMemory.userName!,
        aiName: _currentMemory.aiName!,
        userBirthdate: _userBirthdate!,
        meetStory: _currentMemory.meetStory!,
        userCountryCode: _currentMemory.userCountry!,
        aiCountryCode: _currentMemory.aiCountry!,
      );
    } else {
      // Si faltan datos, continuar con el flujo normal
      Log.w(
        '⚠️ Faltan datos, continuando flujo normal',
        tag: 'CONV_ONBOARDING',
      );
    }
  }

  Future<String?> _showTextInputDialog(OnboardingStep step) async {
    // No mostrar diálogo si ya hay uno abierto
    if (_isDialogOpen) {
      Log.w(
        '⚠️ Diálogo ya abierto, ignorando nueva solicitud',
        tag: 'CONV_ONBOARDING',
      );
      return null;
    }

    // No mostrar teclado si estamos hablando
    if (_isSpeaking || _isTtsPlaying) {
      Log.w('⚠️ No mostrar diálogo durante TTS activo', tag: 'CONV_ONBOARDING');
      return null;
    }

    // Pausar cualquier TTS activo
    if (_isTtsPlaying) {
      Log.d('🛑 Pausando TTS antes de mostrar diálogo', tag: 'CONV_ONBOARDING');
      await _openaiTtsService.stop();
      _safeSetState(() => _isTtsPlaying = false);
    }

    // Marcar que hay un diálogo abierto
    _isDialogOpen = true;
    Log.d('📱 Abriendo diálogo para step: $step', tag: 'CONV_ONBOARDING');

    if (!mounted) return null;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false, // Prevenir cierre accidental
      builder: (context) => _buildInputDialogForStep(step),
    );

    // Marcar que el diálogo se ha cerrado
    _isDialogOpen = false;
    Log.d(
      '📱 Diálogo cerrado, resultado: ${result ?? "null"}',
      tag: 'CONV_ONBOARDING',
    );

    return result;
  }

  Widget _buildInputDialogForStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.askingCountry:
        return _buildCountryInputDialog('¿De dónde eres?', false);
      case OnboardingStep.askingAiCountry:
        return _buildCountryInputDialog('¿De qué país era yo?', true);
      case OnboardingStep.askingBirthdate:
        return _buildDateInputDialog();
      case OnboardingStep.askingAiName:
        return _buildAiNameInputDialog();
      case OnboardingStep.askingName:
      case OnboardingStep.askingMeetStory:
      case OnboardingStep.finalMessage:
      case OnboardingStep.completion:
        return _buildTextInputDialog(step);
    }
  }

  Widget _buildCountryInputDialog(String title, bool isForAi) {
    String? selectedCountryCode;

    return StatefulBuilder(
      builder: (context, setState) => Dialog(
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
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF00FFD4),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              CountryAutocomplete(
                key: ValueKey(
                  'country-dialog-${isForAi ? 'ai' : 'user'}-${DateTime.now().millisecondsSinceEpoch}',
                ),
                selectedCountryCode: selectedCountryCode,
                labelText: isForAi ? 'País de la AI-Chan' : 'Tu país',
                prefixIcon: Icons.flag,
                preferredCountries: isForAi
                    ? const [
                        'JP',
                        'KR',
                        'US',
                        'MX',
                        'BR',
                        'CN',
                        'GB',
                        'SE',
                        'FI',
                        'PL',
                        'DE',
                        'NL',
                        'CA',
                        'AU',
                        'SG',
                        'NO',
                      ]
                    : null,
                onCountrySelected: (code) {
                  setState(() => selectedCountryCode = code);
                },
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
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
                  ElevatedButton(
                    onPressed: selectedCountryCode?.isNotEmpty == true
                        ? () {
                            // 🔧 CONVERTIR CÓDIGO A NOMBRE COMPLETO antes de devolver
                            final countryName = CountriesEs
                                .codeToName[selectedCountryCode!.toUpperCase()];
                            Navigator.of(
                              context,
                            ).pop(countryName ?? selectedCountryCode);
                          }
                        : null,
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
  }

  Widget _buildDateInputDialog() {
    DateTime? selectedDate;
    final dateController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setState) => Dialog(
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
              const Text(
                '¿Cuándo naciste?',
                style: TextStyle(
                  color: Color(0xFF00FFD4),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              BirthDateField(
                controller: dateController,
                userBirthdate: selectedDate,
                onBirthdateChanged: (date) {
                  setState(() => selectedDate = date);
                  dateController.text =
                      '${date.day}/${date.month}/${date.year}';
                },
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
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
                  ElevatedButton(
                    onPressed: selectedDate != null
                        ? () => Navigator.of(context).pop(
                            '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                          )
                        : null,
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
  }

  Widget _buildAiNameInputDialog() {
    String? selectedName;
    final nameController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setState) => Dialog(
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
              const Text(
                '¿Cómo me llamaba yo?',
                style: TextStyle(
                  color: Color(0xFF00FFD4),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              FemaleNameAutocomplete(
                key: ValueKey(
                  'name-dialog-${DateTime.now().millisecondsSinceEpoch}',
                ),
                selectedName: selectedName,
                countryCode: _aiCountry,
                labelText: 'Nombre de la AI-Chan',
                prefixIcon: Icons.smart_toy,
                controller: nameController,
                onNameSelected: (name) {
                  setState(() => selectedName = name);
                },
                onChanged: (name) {
                  setState(() => selectedName = name);
                },
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
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
                  ElevatedButton(
                    onPressed: nameController.text.trim().isNotEmpty
                        ? () => Navigator.of(
                            context,
                          ).pop(nameController.text.trim())
                        : null,
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
  }

  Widget _buildTextInputDialog(OnboardingStep step) {
    // Mensaje contextual según el paso
    String hintText = 'Escribe tu respuesta aquí...';
    String titleText = 'Respuesta por texto';

    switch (step) {
      case OnboardingStep.askingName:
        hintText = 'Escribe tu nombre...';
        titleText = '¿Cómo te llamas?';
        break;
      case OnboardingStep.askingMeetStory:
        hintText = 'Escribe cómo nos conocimos...';
        titleText = '¿Cómo nos conocimos?';
        break;
      case OnboardingStep.finalMessage:
      case OnboardingStep.completion:
        hintText = 'Escribe tu respuesta...';
        titleText = 'Respuesta';
        break;
      default:
        break;
    }

    final textController = TextEditingController();

    return Dialog(
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
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
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
    );
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
    // Asegurar que no queden timers o subscripciones activas de subtítulos
    _progressiveTimer?.cancel();
    _progressiveTimer = null;
    _progressiveSub?.cancel();
    _progressiveSub = null;
    super.dispose();
  }
}

/// Enumeración de los pasos del onboarding conversacional
enum OnboardingStep {
  askingName, // "¿Cómo te llamas?" (nombre del usuario)
  askingCountry, // "¿De qué país eres?" (país del usuario)
  askingBirthdate, // "¿Cuándo naciste?" (fecha de nacimiento del usuario)
  askingAiCountry, // "¿De qué país quieres que sea?" (país de la IA)
  askingAiName, // "¿Cómo quieres llamarme?" (nombre de la IA)
  askingMeetStory, // "¿Cómo nos conocimos?" (historia de cómo se conocieron)
  finalMessage, // "Perfecto! Ahora voy a generar mis recuerdos..."
  completion, // Finalización real del onboarding
}
