import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/onboarding/application/controllers/conversational_onboarding_controller.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:ai_chan/shared/services/hybrid_stt_service.dart';
import 'package:ai_chan/shared/widgets/conversational_subtitles.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'onboarding_screen.dart' show OnboardingFinishCallback;

/// Pantalla de onboarding conversacional refactorizada
/// Separada de la lógica de negocio, usando el patrón Controller
class ConversationalOnboardingScreenRefactored extends StatefulWidget {
  final OnboardingFinishCallback onFinish;
  final void Function()? onClearAllDebug;
  final OnboardingProvider? onboardingProvider;

  const ConversationalOnboardingScreenRefactored({
    super.key,
    required this.onFinish,
    this.onClearAllDebug,
    this.onboardingProvider,
  });

  @override
  State<ConversationalOnboardingScreenRefactored> createState() => _ConversationalOnboardingScreenRefactoredState();
}

class _ConversationalOnboardingScreenRefactoredState extends State<ConversationalOnboardingScreenRefactored>
    with TickerProviderStateMixin {
  // Controller y servicios
  late ConversationalOnboardingController _controller;
  late HybridSttService _hybridSttService;
  late AudioPlayer _audioPlayer;
  late ConversationalSubtitleController _subtitleController;

  // Animaciones
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Control de entrada de texto
  final TextEditingController _textController = TextEditingController();
  bool _showTextInput = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _initializeController();

    // Iniciar el onboarding después de un breve delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _controller.startOnboarding();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    _hybridSttService.dispose();
    _subtitleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _initializeServices() {
    _audioPlayer = AudioPlayer();
    _subtitleController = ConversationalSubtitleController();
    _hybridSttService = HybridSttService();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(duration: const Duration(seconds: 2), vsync: this);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _pulseController.repeat(reverse: true);
  }

  void _initializeController() {
    _controller = ConversationalOnboardingController(
      ttsService: di.getTtsService(),
      hybridSttService: _hybridSttService,
      audioPlayer: _audioPlayer,
      subtitleController: _subtitleController,
    );

    // Escuchar cambios del controlador
    _controller.addListener(() {
      if (mounted) {
        setState(() {});

        // Actualizar nombres en subtítulos cuando cambien
        if (_controller.state.userName != null) {
          _subtitleController.updateNames(userName: _controller.state.userName);
        }
        if (_controller.state.aiName != null) {
          _subtitleController.updateNames(aiName: _controller.state.aiName);
        }

        // Si el onboarding está completo, finalizar
        if (_controller.isComplete && _controller.hasRequiredData) {
          _finishOnboarding();
        }
      }
    });
  }

  void _finishOnboarding() {
    final state = _controller.state;

    // Extraer los datos requeridos del estado
    final userName = state.collectedData['userName'] as String? ?? '';
    final aiName = state.collectedData['aiName'] as String? ?? '';
    final userBirthdayStr = state.collectedData['userBirthday'] as String?;
    final meetStory = state.collectedData['meetStory'] as String? ?? '';
    final userCountryCode = state.collectedData['userCountry'] as String?;
    final aiCountryCode = state.collectedData['aiCountry'] as String?;

    // Parsear fecha de nacimiento
    DateTime? userBirthday;
    if (userBirthdayStr != null) {
      userBirthday = DateTime.tryParse(userBirthdayStr);
    }

    // Validar datos requeridos
    if (userName.isEmpty || aiName.isEmpty || userBirthday == null || meetStory.isEmpty) {
      Log.e('Cannot finish onboarding: missing required data');
      return;
    }

    // Llamar al callback de finalización con todos los parámetros requeridos
    widget.onFinish(
      userName: userName,
      aiName: aiName,
      userBirthday: userBirthday,
      meetStory: meetStory,
      userCountryCode: userCountryCode,
      aiCountryCode: aiCountryCode,
    );
  }

  void _toggleTextInput() {
    setState(() {
      _showTextInput = !_showTextInput;
    });
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _controller.processUserResponse(text, fromTextInput: true);
      _textController.clear();
      setState(() {
        _showTextInput = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMainContent()),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            'AI-chan está despertando...',
            style: TextStyle(
              color: AppColors.primary.withValues(alpha: 0.8),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (widget.onClearAllDebug != null)
            IconButton(
              icon: Icon(Icons.refresh, color: AppColors.primary.withValues(alpha: 0.6)),
              onPressed: widget.onClearAllDebug,
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        Expanded(child: Center(child: _buildAvatarSection())),
        if (_subtitleController.hasVisibleContent)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ConversationalSubtitles(controller: _subtitleController),
          ),
      ],
    );
  }

  Widget _buildAvatarSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.3),
                  AppColors.primary.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(Icons.person, size: 80, color: AppColors.primary.withValues(alpha: 0.8)),
          ),
          builder: (context, child) {
            return Transform.scale(scale: _pulseAnimation.value, child: child);
          },
        ),
        const SizedBox(height: 24),
        _buildStatusIndicator(),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    String status;
    Color color;

    if (_controller.isSpeaking) {
      status = 'Hablando...';
      color = AppColors.primary;
    } else if (_controller.isListening) {
      status = 'Escuchando...';
      color = Colors.green;
    } else if (_controller.isThinking) {
      status = 'Pensando...';
      color = Colors.orange;
    } else {
      status = 'En espera...';
      color = AppColors.primary.withValues(alpha: 0.5);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_showTextInput) _buildTextInput(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleTextInput,
                  icon: Icon(_showTextInput ? Icons.mic : Icons.keyboard),
                  label: Text(_showTextInput ? 'Voz' : 'Texto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _controller.retryCurrentStep,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Escribe tu respuesta...',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
            ),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _sendTextMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Enviar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Función helper para crear perfil desde el estado
dynamic createProfileFromState(dynamic state) {
  // Por ahora retorna un map básico, se puede mejorar más tarde
  return {
    'userName': state.userName,
    'userCountry': state.userCountry,
    'userBirthday': state.userBirthday,
    'aiName': state.aiName,
    'aiCountry': state.aiCountry,
    'meetStory': state.meetStory,
  };
}
