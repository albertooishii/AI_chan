import 'package:flutter/material.dart';
import 'dart:async';
import '../controllers/voice_call_controller.dart';
import '../../../shared/ai_providers/core/services/audio/centralized_microphone_amplitude_service.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';

/// 🎯 Widget de animación de ondas cyberpunk alrededor del avatar
class VoiceWaveAnimation extends StatefulWidget {
  const VoiceWaveAnimation({
    super.key,
    required this.isActive,
    required this.amplitude,
    required this.child,
  });

  final bool isActive;
  final double amplitude; // 0.0 - 1.0
  final Widget child;

  @override
  State<VoiceWaveAnimation> createState() => _VoiceWaveAnimationState();
}

class _VoiceWaveAnimationState extends State<VoiceWaveAnimation>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    if (!widget.isActive) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_waveController, _pulseController]),
      builder: (final context, final child) {
        return CustomPaint(
          painter: VoiceWavePainter(
            waveProgress: _waveController.value,
            pulseProgress: _pulseController.value,
            amplitude: widget.amplitude,
          ),
          child: widget.child,
        );
      },
    );
  }
}

class VoiceWavePainter extends CustomPainter {
  VoiceWavePainter({
    required this.waveProgress,
    required this.pulseProgress,
    required this.amplitude,
  });
  final double waveProgress;
  final double pulseProgress;
  final double amplitude;

  @override
  void paint(final Canvas canvas, final Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Dibuja ondas cyberpunk basadas en la amplitud
    for (int i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = AppColors.cyberpunkYellow.withValues(
          alpha: (0.3 - i * 0.1) * amplitude,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final waveRadius =
          radius + (i * 30) + (amplitude * 50) + (pulseProgress * 20);

      canvas.drawCircle(center, waveRadius, paint);
    }
  }

  @override
  bool shouldRepaint(final VoiceWavePainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
        oldDelegate.pulseProgress != pulseProgress ||
        oldDelegate.amplitude != amplitude;
  }
}

/// 🎯 Pantalla principal de Voice Chat con diseño cyberpunk
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with TickerProviderStateMixin {
  late final VoiceCallController _controller;
  late final AnimationController _fadeController;
  late final AnimationController _micController;

  // Stream para amplitud del micrófono
  StreamSubscription? _amplitudeSubscription;
  double _currentAmplitude = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = VoiceCallController();
    _controller.addListener(_onControllerChange);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _micController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeController.forward();

    // Suscribirse al stream de amplitud del micrófono
    _setupAmplitudeListener();
  }

  void _onControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setupAmplitudeListener() {
    final amplitudeService = CentralizedMicrophoneAmplitudeService.instance;
    _amplitudeSubscription = amplitudeService.amplitudeStream.listen((
      final amplitude,
    ) {
      if (mounted) {
        setState(() {
          _currentAmplitude = amplitude;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _fadeController.dispose();
    _micController.dispose();
    _amplitudeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: FadeTransition(
          opacity: _fadeController,
          child: const Text(
            '📞 AI-chan Voice',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w300,
              letterSpacing: 2.0,
              fontSize: 20,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          ScaleTransition(
            scale: _micController,
            child: IconButton(
              icon: Icon(
                _controller.isMuted ? Icons.mic_off : Icons.mic,
                color: _controller.isMuted ? Colors.red : AppColors.secondary,
              ),
              onPressed: () {
                _micController.forward().then((_) {
                  _micController.reverse();
                });
                _controller.toggleMute();
              },
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeController,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Avatar con animación de ondas
              VoiceWaveAnimation(
                isActive: _controller.isInCall && !_controller.isMuted,
                amplitude: _currentAmplitude,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _controller.isInCall
                          ? AppColors.cyberpunkYellow
                          : AppColors.primary,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_controller.isInCall
                                    ? AppColors.cyberpunkYellow
                                    : AppColors.primary)
                                .withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Container(
                      color: Colors.grey[900],
                      child: Icon(
                        Icons.person,
                        size: 80,
                        color: _controller.isInCall
                            ? AppColors.cyberpunkYellow
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Estado actual con animación
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                child: Text(
                  _controller.statusText,
                  style: const TextStyle(
                    color: AppColors.cyberpunkYellow,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(flex: 2),

              // Controles principales en estilo minimalista
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón mute (solo visible durante llamada)
                  if (_controller.isInCall)
                    _buildCyberpunkButton(
                      icon: _controller.isMuted ? Icons.mic_off : Icons.mic,
                      onPressed: () {
                        _micController.forward().then((_) {
                          _micController.reverse();
                        });
                        _controller.toggleMute();
                      },
                      isActive: !_controller.isMuted,
                      color: _controller.isMuted
                          ? Colors.red
                          : AppColors.secondary,
                    ),

                  // Botón principal llamar/colgar
                  _buildCyberpunkButton(
                    icon: _controller.isInCall ? Icons.call_end : Icons.call,
                    onPressed: _controller.isInCall
                        ? _controller.endCall
                        : _controller.startCall,
                    isActive: true,
                    color: _controller.isInCall
                        ? Colors.red
                        : AppColors.cyberpunkYellow,
                    size: 80,
                  ),

                  // Indicador de escucha automática (solo visible durante llamada)
                  if (_controller.isInCall)
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _controller.isListening
                              ? Colors.green
                              : AppColors.primary,
                          width: 2,
                        ),
                        color: _controller.isListening
                            ? Colors.green.withOpacity(0.2)
                            : Colors.black.withOpacity(0.3),
                        boxShadow: _controller.isListening
                            ? [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _controller.isListening ? Icons.mic : Icons.mic_none,
                        color: _controller.isListening
                            ? Colors.green
                            : AppColors.primary,
                        size: 32,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Toggle de modo de voz
              if (_controller.isInCall)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(25),
                    color: Colors.black.withOpacity(0.3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _controller.useHybridMode
                            ? '🔄 Híbrido (Automático)'
                            : '⚡ Realtime',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _controller.toggleVoiceMode,
                        child: Container(
                          width: 50,
                          height: 25,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            color: _controller.useHybridMode
                                ? AppColors.primary
                                : Colors.orange,
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: _controller.useHybridMode
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Botón de prueba de texto (solo cuando no está en llamada)
              if (!_controller.isInCall)
                _buildCyberpunkButton(
                  icon: Icons.chat,
                  onPressed: () => _controller.processTextInput(
                    'Hola AI-chan, ¿cómo estás?',
                  ),
                  isActive: true,
                  color: AppColors.primary,
                ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCyberpunkButton({
    required final IconData icon,
    required final VoidCallback onPressed,
    required final bool isActive,
    required final Color color,
    final double size = 60,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? color : color.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(size / 2),
          child: Icon(
            icon,
            color: isActive ? color : color.withValues(alpha: 0.7),
            size: size * 0.4,
          ),
        ),
      ),
    );
  }
}
