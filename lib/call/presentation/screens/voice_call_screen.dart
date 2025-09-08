import 'package:ai_chan/call/presentation/controllers/voice_call_screen_controller.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/presentation/widgets/cyberpunk_painters.dart';
import 'package:ai_chan/core/di.dart' as di;

class VoiceCallScreen extends StatefulWidget {
  // ✅ Bounded Context Abstraction

  const VoiceCallScreen({super.key, this.incoming = false});
  final bool incoming;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late VoiceCallScreenController _controller;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _initializeController();
    _initializeAnimations();
  }

  void _initializeController() {
    // ✅ DDD: Usar VoiceCallApplicationService con DI directo
    final voiceCallService = di.getVoiceCallApplicationService();

    _controller = VoiceCallScreenController(
      callType: widget.incoming ? CallType.incoming : CallType.outgoing,
      voiceCallService: voiceCallService,
    );

    _controller.addListener(_onControllerStateChanged);
    _controller.initialize();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  void _onControllerStateChanged() {
    if (!mounted) return;

    final state = _controller.state;

    // Manejar navegación cuando la llamada termine
    if (state.phase == CallPhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }

    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerStateChanged);
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _controller.hangupCall(),
        ),
        title: Text(
          _getCallTitle(state),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (state.phase == CallPhase.active && state.callDuration > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  _formatDuration(state.callDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Fondo con efectos cyberpunk
          _buildCyberpunkBackground(),

          // Contenido principal
          Column(
            children: [
              const Spacer(),

              // Avatar y animación de ondas
              _buildAvatarSection(state),

              const SizedBox(height: 40),

              // Subtítulos de conversación
              _buildSubtitlesSection(state),

              const Spacer(),

              // Controles de llamada
              _buildCallControls(state),

              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }

  String _getCallTitle(final VoiceCallState state) {
    switch (state.phase) {
      case CallPhase.initializing:
        return 'Iniciando llamada...';
      case CallPhase.ringing:
        return state.isIncoming ? 'Llamada entrante' : 'Llamando...';
      case CallPhase.connecting:
        return 'Conectando...';
      case CallPhase.active:
        return 'En llamada';
      case CallPhase.ending:
        return 'Finalizando...';
      case CallPhase.ended:
        return 'Llamada finalizada';
    }
  }

  String _formatDuration(final int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCyberpunkBackground() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: CyberpunkGlowPainter(
            baseColor: Colors.cyanAccent,
            accentColor: Colors.pinkAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection(final VoiceCallState state) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animación de ondas de sonido
          AnimatedBuilder(
            animation: _animationController,
            builder: (final context, final child) {
              return CustomPaint(
                painter: WavePainter(
                  animation: _animationController.value,
                  soundLevel: state.soundLevel,
                  baseColor: Colors.cyanAccent,
                  accentColor: Colors.pinkAccent,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),

          // Avatar circular
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withAlpha((0.7 * 255).round()),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(60),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (final context, final error, final stackTrace) {
                  return Container(
                    color: Colors.cyanAccent.withAlpha((0.3 * 255).round()),
                    child: const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlesSection(final VoiceCallState state) {
    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha((0.7 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.cyanAccent.withAlpha((0.3 * 255).round()),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.aiText.isNotEmpty) ...[
              Text(
                '${state.aiLabel}:',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.aiText,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (state.userText.isNotEmpty) ...[
              Text(
                '${state.userLabel}:',
                style: const TextStyle(
                  color: Colors.pinkAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.userText,
                style: const TextStyle(
                  color: Colors.pinkAccent,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCallControls(final VoiceCallState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Botón aceptar (solo para llamadas entrantes no aceptadas)
        if (state.showAcceptButton)
          _buildControlButton(
            icon: Icons.call,
            color: Colors.green,
            onTap: () => _controller.acceptIncomingCall(),
          ),

        // Botón mute/unmute
        if (state.phase == CallPhase.active)
          _buildControlButton(
            icon: state.isMuted ? Icons.mic_off : Icons.mic,
            color: state.isMuted ? Colors.grey : Colors.cyanAccent,
            onTap: () => _controller.toggleMute(),
          ),

        // Botón colgar
        if (state.canHangup)
          _buildControlButton(
            icon: Icons.call_end,
            color: Colors.red,
            onTap: () => _controller.hangupCall(),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required final IconData icon,
    required final Color color,
    required final VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              color.withAlpha((0.8 * 255).round()),
              color.withAlpha((0.6 * 255).round()),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha((0.7 * 255).round()),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: color, width: 2.5),
        ),
        child: Icon(icon, color: Colors.white, size: 36),
      ),
    );
  }
}
