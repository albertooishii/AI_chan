import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart'; // Using shared exports for infrastructure

/// Controlador global para subtítulos conversacionales en tiempo real
class ConversationalSubtitleController {
  ConversationalSubtitleController({final bool debug = false}) {
    _streamingController = StreamingSubtitleController(debug: debug);
  }
  _ConversationalSubtitlesState? _state;
  late StreamingSubtitleController _streamingController;

  void _attach(final _ConversationalSubtitlesState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Actualiza los nombres para mostrar en los subtítulos
  void updateNames({final String? userName, final String? aiName}) {
    _state?.updateNames(userName: userName, aiName: aiName);
  }

  /// Maneja chunks de IA en tiempo real (nuevo sistema rápido)
  void handleAiChunk(
    final String chunk, {
    required final bool audioStarted,
    required final bool suppressFurther,
  }) {
    _streamingController.handleAiChunk(
      chunk,
      audioStarted: audioStarted,
      suppressFurther: suppressFurther,
    );
  }

  /// Maneja transcripciones del usuario
  void handleUserTranscription(final String text) {
    _streamingController.handleUserTranscription(text);
  }

  /// Muestra texto del usuario instantáneamente (compatibility)
  void showUserText(final String text) {
    handleUserTranscription(text);
  }

  /// Limpia todos los subtítulos
  void clearAll() {
    _streamingController.clearAll();
  }

  /// Verifica si hay contenido visible
  bool get hasVisibleContent {
    return _streamingController.ai.value.isNotEmpty ||
        _streamingController.user.value.isNotEmpty;
  }

  /// Acceso al controlador de streaming interno
  StreamingSubtitleController get streaming => _streamingController;

  void dispose() {
    _streamingController.dispose();
  }
}

/// Widget de subtítulos cyberpunk para el onboarding conversacional
/// Usa el nuevo sistema de streaming en tiempo real
class ConversationalSubtitles extends StatefulWidget {
  const ConversationalSubtitles({
    super.key,
    required this.controller,
    this.maxHeight = 200,
  });
  final ConversationalSubtitleController controller;
  final double maxHeight;

  @override
  State<ConversationalSubtitles> createState() =>
      _ConversationalSubtitlesState();
}

class _ConversationalSubtitlesState extends State<ConversationalSubtitles> {
  final ScrollController _scrollController = ScrollController();

  // Nombres dinámicos para los subtítulos
  String _userName = 'TÚ';
  String _aiName = 'AI-CHAN';

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);

    // Escuchar cambios en los subtítulos para auto-scroll
    widget.controller._streamingController.ai.addListener(_onSubtitleChange);
    widget.controller._streamingController.user.addListener(_onSubtitleChange);
  }

  @override
  void dispose() {
    widget.controller._detach();
    widget.controller._streamingController.ai.removeListener(_onSubtitleChange);
    widget.controller._streamingController.user.removeListener(
      _onSubtitleChange,
    );
    _scrollController.dispose();
    super.dispose();
  }

  void _onSubtitleChange() {
    if (mounted) {
      setState(() {});
      _autoScroll();
    }
  }

  // Método para actualizar los nombres mostrados en los subtítulos
  void updateNames({final String? userName, final String? aiName}) {
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
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(final BuildContext context) {
    final streaming = widget.controller._streamingController;

    return ValueListenableBuilder<String>(
      valueListenable: streaming.ai,
      builder: (final context, final aiText, _) {
        return ValueListenableBuilder<String>(
          valueListenable: streaming.user,
          builder: (final context, final userText, _) {
            // Solo mostrar el contenedor si hay contenido visible
            if (aiText.isEmpty && userText.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
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
                    // Subtítulo de la IA en tiempo real
                    if (aiText.isNotEmpty) ...[
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
                      CyberpunkRealtimeSubtitle(
                        text: aiText,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontFamily: 'FiraMono',
                          height: 1.4,
                        ),
                        scramblePerChar: const Duration(milliseconds: 80),
                        glitchProbability: 0.1,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Subtítulo del usuario
                    if (userText.isNotEmpty) ...[
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
                      Text(
                        userText,
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 16,
                          fontFamily: 'FiraMono',
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
