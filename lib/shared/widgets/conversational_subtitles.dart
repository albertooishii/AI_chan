import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/call/presentation/widgets/cyberpunk_subtitle.dart';
import 'package:ai_chan/shared/controllers/audio_subtitle_controller.dart';

/// Controlador global para subtítulos conversacionales
class ConversationalSubtitleController {
  _ConversationalSubtitlesState? _state;

  void _attach(_ConversationalSubtitlesState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Actualiza los nombres para mostrar en los subtítulos
  void updateNames({String? userName, String? aiName}) {
    _state?.updateNames(userName: userName, aiName: aiName);
  }

  /// Inicia revelado gradual de texto de IA con duración específica
  void startAiReveal(String text, {Duration? estimatedDuration}) {
    _state?.startAiReveal(text, estimatedDuration: estimatedDuration);
  }

  /// Muestra texto del usuario instantáneamente
  void showUserText(String text) {
    _state?.showUserText(text);
  }

  /// Limpia todos los subtítulos
  void clearAll() {
    _state?.clearAll();
  }

  /// Verifica si hay contenido visible
  bool get hasVisibleContent {
    return _state?._hasVisibleContent ?? false;
  }
}

/// Widget de subtítulos cyberpunk para el onboarding conversacional
/// Usa el mismo sistema que ChatBubble para revelado gradual
class ConversationalSubtitles extends StatefulWidget {
  final ConversationalSubtitleController controller;
  final double maxHeight;

  const ConversationalSubtitles({
    super.key,
    required this.controller,
    this.maxHeight = 200,
  });

  @override
  State<ConversationalSubtitles> createState() =>
      _ConversationalSubtitlesState();
}

class _ConversationalSubtitlesState extends State<ConversationalSubtitles> {
  final ScrollController _scrollController = ScrollController();
  final AudioSubtitleController _aiController = AudioSubtitleController();
  final AudioSubtitleController _userController = AudioSubtitleController();

  Timer? _revealTimer;
  String _currentAiText = '';
  String _currentUserText = '';
  bool _isRevealing = false;

  // Nombres dinámicos para los subtítulos
  String _userName = 'TÚ';
  String _aiName = 'AI-CHAN';

  // Getter para verificar si hay contenido visible
  bool get _hasVisibleContent =>
      _currentAiText.isNotEmpty || _currentUserText.isNotEmpty || _isRevealing;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void dispose() {
    widget.controller._detach();
    _revealTimer?.cancel();
    _scrollController.dispose();
    _aiController.dispose();
    _userController.dispose();
    super.dispose();
  }

  // Método para iniciar revelado gradual de texto de IA con duración personalizada
  void startAiReveal(String text, {Duration? estimatedDuration}) {
    if (text.isEmpty || text == _currentAiText) return;

    // Limpiar subtítulos anteriores cuando hay nueva respuesta de IA
    if (_currentAiText.isNotEmpty || _currentUserText.isNotEmpty) {
      setState(() {
        _currentUserText = ''; // Limpiar respuesta anterior del usuario
      });
      _userController.clear();
    }

    _currentAiText = text;
    _isRevealing = true;
    _aiController.clear();

    // Usar duración proporcionada o calcular basada en palabras
    final Duration finalDuration;
    if (estimatedDuration != null && estimatedDuration.inMilliseconds > 0) {
      // Usar duración real del TTS
      finalDuration = estimatedDuration;
    } else {
      // Fallback: calcular basado en palabras (como antes)
      const wordsPerSecond = 3.0; // Velocidad de revelado
      final words = text.split(' ').length;
      finalDuration = Duration(
        milliseconds: (words / wordsPerSecond * 1000).round().clamp(1500, 8000),
      );
    }

    // Cancelar timer anterior
    _revealTimer?.cancel();

    // Iniciar revelado progresivo
    final startTime = DateTime.now();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      final progress = (elapsed.inMilliseconds / finalDuration.inMilliseconds)
          .clamp(0.0, 1.0);

      if (progress >= 1.0) {
        _aiController.showFullTextInstant(text);
        _isRevealing = false;
        timer.cancel();
        _autoScroll();

        // NO limpiar automáticamente - mantener visible hasta nueva interacción
        // El subtítulo se limpiará cuando haya nueva respuesta AI
      } else {
        _aiController.updateProportional(elapsed, text, finalDuration);
        if (progress > 0.1) _autoScroll(); // Auto-scroll después del primer 10%
      }

      // Forzar rebuild cuando cambia el estado de revelado
      if (mounted) setState(() {});
    });
  }

  // Método para mostrar texto del usuario instantáneamente
  void showUserText(String text) {
    if (text.isEmpty || text == _currentUserText) return;

    // MANTENER el subtítulo de AI visible cuando el usuario habla
    // para crear un diálogo claramente visible (pregunta -> respuesta)

    setState(() {
      _currentUserText = text;
    });
    _userController.showFullTextInstant(text);
    _autoScroll();

    // Limpiar texto del usuario después de un tiempo más largo para permitir lectura
    Timer(const Duration(seconds: 12), () {
      if (_currentUserText == text && mounted) {
        setState(() {
          _currentUserText = '';
        });
        _userController.clear();
      }
    });
  }

  void clearAll() {
    _revealTimer?.cancel();
    setState(() {
      _isRevealing = false;
      _currentAiText = '';
      _currentUserText = '';
    });
    _aiController.clear();
    _userController.clear();
  }

  // Método para actualizar los nombres mostrados en los subtítulos
  void updateNames({String? userName, String? aiName}) {
    setState(() {
      if (userName != null && userName.trim().isNotEmpty) {
        _userName = userName.toUpperCase();
      }
      if (aiName != null && aiName.trim().isNotEmpty) {
        _aiName = aiName.toUpperCase();
      }
    });
  }

  void _autoScroll() {
    // Auto-scroll al final cuando hay contenido nuevo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Solo mostrar el contenedor si hay contenido visible
    if (!_hasVisibleContent) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subtítulo de la IA con animación gradual
            StreamBuilder<String>(
              stream: _aiController.progressiveTextStream,
              builder: (context, snapshot) {
                final aiText = snapshot.data ?? '';
                if (aiText.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Indicador de que es la IA
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_aiName:',
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Subtítulo cyberpunk con animación para la IA
                    CyberpunkRealtimeSubtitle(
                      text: aiText,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 16,
                        fontFamily: 'FiraMono',
                        height: 1.4,
                      ),
                      scramblePerChar: const Duration(milliseconds: 120),
                      glitchProbability: 0.15,
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),

            // Subtítulo del usuario
            StreamBuilder<String>(
              stream: _userController.progressiveTextStream,
              builder: (context, snapshot) {
                final userText = snapshot.data ?? '';
                if (userText.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Indicador de que es el usuario
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_userName:',
                          style: TextStyle(
                            color: AppColors.secondary.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Subtítulo instantáneo para el usuario (sin animación)
                    Text(
                      userText,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 16,
                        fontFamily: 'FiraMono',
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
