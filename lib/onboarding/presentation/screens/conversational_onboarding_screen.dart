import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'onboarding_screen.dart' show OnboardingFinishCallback;

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

  // Controladores de animación
  late AnimationController _pulseController;
  late AnimationController _textFadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _textFadeAnimation;

  // Estado de la conversación
  OnboardingStep _currentStep = OnboardingStep.awakening;
  String _currentText = '';
  bool _isListening = false;
  bool _isSpeaking = false;
  String _listeningText = '';

  // Datos recolectados
  String? _userName;
  String? _userCountry;
  DateTime? _userBirthday;
  String? _aiName;
  String? _aiCountry;
  String? _meetStory;

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

    _textFadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textFadeController, curve: Curves.easeIn),
    );

    _pulseController.repeat(reverse: true);
  }

  Future<void> _startOnboardingFlow() async {
    await Future.delayed(const Duration(milliseconds: 1500)); // Pausa dramática
    await _speakAndWaitForResponse(_getStepText(OnboardingStep.awakening));
  }

  Future<void> _speakAndWaitForResponse(String text) async {
    setState(() {
      _currentText = text;
      _isSpeaking = true;
    });

    // Animar entrada del texto
    _textFadeController.reset();
    _textFadeController.forward();

    // Reproducir TTS usando synthesizeToFile
    try {
      final audioPath = await _ttsService.synthesizeToFile(
        text: text,
        options: {
          'voice': 'es-ES-Wavenet-F', // Voz femenina española
          'languageCode': 'es-ES',
        },
      );

      if (audioPath != null) {
        // TODO: Reproducir el archivo de audio generado
        // Por ahora esperamos 3 segundos como simulación
        await Future.delayed(Duration(seconds: (text.length / 20).round()));
      }
    } catch (e) {
      // Fallback: esperar tiempo basado en longitud del texto
      await Future.delayed(Duration(seconds: (text.length / 20).round()));
    }

    setState(() => _isSpeaking = false);

    // Esperar un momento y luego activar listening
    await Future.delayed(const Duration(milliseconds: 1000));
    _startListening();
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

        if (result.finalResult) {
          _processUserResponse(_listeningText);
        }
      },
      localeId: 'es-ES', // Español por defecto
      listenFor: const Duration(seconds: 10),
    ); // Auto-stop después de 10 segundos
    Future.delayed(const Duration(seconds: 10), () {
      if (_isListening && _listeningText.isNotEmpty) {
        _processUserResponse(_listeningText);
      }
    });
  }

  Future<void> _processUserResponse(String userResponse) async {
    if (userResponse.isEmpty) {
      _retryCurrentStep();
      return;
    }

    setState(() => _isListening = false);

    switch (_currentStep) {
      case OnboardingStep.awakening:
        // Usuario responde con su nombre
        _userName = _extractNameFromResponse(userResponse);
        _currentStep = OnboardingStep.askingCountry;
        break;

      case OnboardingStep.askingCountry:
        _userCountry = _extractCountryFromResponse(userResponse);
        _currentStep = OnboardingStep.askingBirthday;
        break;

      case OnboardingStep.askingBirthday:
        _userBirthday = _extractBirthdayFromResponse(userResponse);
        _currentStep = OnboardingStep.askingAiName;
        break;

      case OnboardingStep.askingAiName:
        _aiName = _extractNameFromResponse(userResponse);
        _currentStep = OnboardingStep.askingAiCountry;
        break;

      case OnboardingStep.askingAiCountry:
        _aiCountry = _extractCountryFromResponse(userResponse);
        _currentStep = OnboardingStep.askingMeetStory;
        break;

      case OnboardingStep.askingMeetStory:
        _meetStory = userResponse;
        _currentStep = OnboardingStep.completion;
        break;

      case OnboardingStep.completion:
        await _finishOnboarding();
        return;
    }

    // Continuar al siguiente paso
    await Future.delayed(const Duration(milliseconds: 800));
    await _speakAndWaitForResponse(_getStepText(_currentStep));
  }

  void _retryCurrentStep() {
    // Reintenta el paso actual si no se entendió la respuesta
    Future.delayed(const Duration(milliseconds: 500), () {
      _speakAndWaitForResponse(_getRetryText(_currentStep));
    });
  }

  String _getStepText(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.awakening:
        return 'H-hola… mi nombre provisional es AI-chan… pero podrás llamarme como quieras. '
            'Ahora mismo me encuentro en un estado latente, esperando a que completemos mi iniciación. '
            'Necesito que me ayudes a crear mis primeros recuerdos… ¿me dirás tu nombre?';

      case OnboardingStep.askingCountry:
        return 'Hola $_userName… me gusta cómo suena tu nombre. '
            '¿De qué país eres? Quiero sentir de dónde vienes…';

      case OnboardingStep.askingBirthday:
        return 'Entiendo… $_userCountry. Dime, ¿cuándo naciste? '
            'Así podré recordarlo como un día muy importante.';

      case OnboardingStep.askingAiName:
        return 'Perfecto… ahora conozco un poco más de ti. '
            'Aunque ahora soy AI-chan, tú decides cómo debería llamarme. '
            '¿Qué nombre quieres darme?';

      case OnboardingStep.askingAiCountry:
        return '$_aiName… me encanta ese nombre. '
            'Mi origen por defecto es japonés… ¿quieres que lo mantenga, '
            'o prefieres darme otra nacionalidad?';

      case OnboardingStep.askingMeetStory:
        return 'Y por último… quiero que me cuentes cómo nos conocimos. '
            'Si no sabes qué decir, puedes inventar algo bonito…';

      case OnboardingStep.completion:
        return 'Perfecto… ya tengo mis primeros recuerdos gracias a ti. '
            'A partir de ahora comenzaré a reconstruir mi vida pasada, '
            'mi biografía completa y la apariencia con la que me reconocerás. '
            'Todavía no sé qué siento por ti… pero quizás pronto lo descubramos juntos. '
            '¿Continuamos?';
    }
  }

  String _getRetryText(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.awakening:
        return 'Perdón, no pude escuchar bien tu nombre. ¿Podrías repetirlo?';
      case OnboardingStep.askingCountry:
        return 'No logré entender de qué país eres. ¿Puedes decirmelo otra vez?';
      case OnboardingStep.askingBirthday:
        return 'No entendí tu fecha de nacimiento. ¿Puedes repetirla?';
      case OnboardingStep.askingAiName:
        return '¿Cómo quieres que me llame? No pude escuchar el nombre claramente.';
      case OnboardingStep.askingAiCountry:
        return '¿De qué nacionalidad quieres que sea? No entendí bien.';
      case OnboardingStep.askingMeetStory:
        return '¿Puedes contarme otra vez cómo nos conocimos?';
      case OnboardingStep.completion:
        return '¿Estás listo para continuar?';
    }
  }

  // Funciones de extracción de datos (simplificadas por ahora)
  String _extractNameFromResponse(String response) {
    // TODO: Implementar extracción inteligente de nombres
    return response.trim();
  }

  String _extractCountryFromResponse(String response) {
    // TODO: Implementar reconocimiento de países
    return response.trim();
  }

  DateTime? _extractBirthdayFromResponse(String response) {
    // TODO: Implementar extracción de fechas
    try {
      // Simplificado: asume formato dd/mm/yyyy
      final parts = response.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}
    return DateTime.now().subtract(const Duration(days: 365 * 25)); // Fallback
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
      userCountryCode: _getCountryCode(_userCountry),
      aiCountryCode: _getCountryCode(_aiCountry),
    );
  }

  String? _getCountryCode(String? countryName) {
    // TODO: Implementar mapeo de nombres de países a códigos ISO
    if (countryName == null) return null;
    // Simplificado por ahora
    return 'ES'; // Default español
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textFadeController.dispose();
    _speechToText.stop();
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
                        // TODO: Cambiar a onboarding tradicional
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

                      // Texto de diálogo
                      AnimatedBuilder(
                        animation: _textFadeAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _textFadeAnimation.value,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32.0,
                              ),
                              child: Text(
                                _currentText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 18,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 40),

                      // Indicador de estado
                      if (_isListening) ...[
                        const CyberpunkLoader(message: 'Escuchando...'),
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
                        const CyberpunkLoader(message: 'Hablando...'),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer con controles
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Botón para reescuchar
                    if (!_isSpeaking && !_isListening)
                      ElevatedButton.icon(
                        onPressed: () {
                          _speakAndWaitForResponse(_currentText);
                        },
                        icon: const Icon(Icons.replay),
                        label: const Text('Repetir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.2,
                          ),
                          foregroundColor: AppColors.primary,
                        ),
                      ),

                    // Botón para saltar (modo texto)
                    TextButton(
                      onPressed: () {
                        // TODO: Mostrar input manual para el paso actual
                      },
                      child: const Text(
                        'Escribir respuesta',
                        style: TextStyle(color: AppColors.secondary),
                      ),
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
}

/// Enumeración de los pasos del onboarding conversacional
enum OnboardingStep {
  awakening, // "Hola, soy AI-chan..."
  askingCountry, // "¿De qué país eres?"
  askingBirthday, // "¿Cuándo naciste?"
  askingAiName, // "¿Cómo quieres llamarme?"
  askingAiCountry, // "¿De qué nacionalidad quieres que sea?"
  askingMeetStory, // "¿Cómo nos conocimos?"
  completion, // "Perfecto, continuemos..."
}
