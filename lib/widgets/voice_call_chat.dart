import 'package:record/record.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../services/openai_service.dart';
import '../services/voice_call_controller.dart';
import '../services/voice_call_summary_service.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'voice_call_painters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cyberpunk_subtitle.dart';

class VoiceCallChat extends StatefulWidget {
  const VoiceCallChat({super.key});

  @override
  State<VoiceCallChat> createState() => _VoiceCallChatState();
}

class _VoiceCallChatState extends State<VoiceCallChat> with SingleTickerProviderStateMixin {
  bool _hangupInProgress = false;
  bool _hangupNoticeShown = false;
  // Debug UI subtítulos
  final bool _subtitleUiDebug = false; // silenciado por defecto para no spamear logs de subtítulos

  Future<void> _hangUp() async {
    if (_hangupInProgress) return;
    _hangupInProgress = true;

    // Mute inmediato para cortar el micrófono en UI
    controller.setMuted(true);

    // Capturar provider antes de navegar
    ChatProvider? chat;
    try {
      if (mounted) chat = context.read<ChatProvider>();
    } catch (_) {}

    // Parar animación y timers antes de cerrar la pantalla
    try {
      _subtitleTimer?.cancel();
      _userSubtitleTimer?.cancel();
      _levelSub?.cancel();
      _controller.stop();
    } catch (_) {}

    // Reproducir tono de colgado en background y cerrar la pantalla inmediatamente
    try {
      unawaited(controller.playHangupTone());
    } catch (_) {}

    // Navegar para cerrar la pantalla inmediatamente
    if (mounted) {
      try {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          nav.popUntil((route) => route.isFirst);
        }
      } catch (_) {
        try {
          final rootNav = Navigator.of(context, rootNavigator: true);
          if (rootNav.canPop()) {
            rootNav.popUntil((route) => route.isFirst);
          } else {
            unawaited(rootNav.maybePop());
          }
        } catch (_) {}
      }
    }

    // Limpieza en background: detener sesión de voz/mic y guardar resumen
    unawaited(_performBackgroundCleanup(chat));
  }

  Future<void> _performBackgroundCleanup(ChatProvider? chat) async {
    debugPrint('🧹 Iniciando limpieza en background después de colgar');
    try {
      debugPrint('🧹 Deteniendo controller...');
      await controller.stop(keepFxPlaying: true).timeout(const Duration(milliseconds: 800));
      debugPrint('🧹 Controller detenido');
    } catch (e) {
      debugPrint('🧹 Error deteniendo controller: $e');
    }

    try {
      debugPrint('🧹 Deteniendo grabadora...');
      await _recorder.stop();
      debugPrint('🧹 Grabadora detenida');
    } catch (e) {
      debugPrint('🧹 Error deteniendo grabadora: $e');
    }

    try {
      debugPrint('🧹 Disponiendo grabadora...');
      await _recorder.dispose();
      debugPrint('🧹 Grabadora dispuesta');
    } catch (e) {
      debugPrint('🧹 Error disponiendo grabadora: $e');
    }

    try {
      debugPrint('🧹 Guardando resumen de llamada...');
      await _saveCallSummaryIfAny(chat);
      debugPrint('🧹 Proceso de resumen completado');
    } catch (e) {
      debugPrint('🧹 Error guardando resumen: $e');
    }
    debugPrint('🧹 Limpieza en background finalizada');
  }

  // Sistema de subtítulos con concatenación
  String _currentAiSubtitle = '';
  String _accumulatedFragments = ''; // Acumular fragmentos hasta tener frase completa
  String _currentUserSubtitle = ''; // Subtítulos del usuario
  bool _hideSubtitles = false;
  Timer? _subtitleTimer;
  Timer? _userSubtitleTimer;
  // Detección de revelado progresivo (para ignorar reinicio con prefijos cortos)
  bool _progressiveRevealActive = false;
  bool _revealStarted = false; // sentinel recibido
  int _lastLoggedFullLen = -1; // para suprimir logs duplicados del mismo length

  final OpenAIService openai = OpenAIService();
  late final VoiceCallController controller;
  final AudioRecorder _recorder = AudioRecorder();
  bool _muted = false;
  StreamSubscription<double>? _levelSub;

  void _showAiSubtitle(String text) {
    if (!mounted || _hideSubtitles) return;

    // Sentinel de inicio de revelado desde controller
    if (text == '__REVEAL__') {
      _revealStarted = true;
      _progressiveRevealActive = true;
      // Resetear texto previo
      if (_currentAiSubtitle.isNotEmpty) {
        _currentAiSubtitle = '';
      }
      if (_subtitleUiDebug) debugPrint('👁️ [SUB-UI] Sentinel recibido: iniciar revelado (reset previo)');
      return; // no mostrar nada todavía
    }

    // Detectar si es texto word-by-word (fragmentos) o texto fluido (completo)
    final trimmed = text.trim();
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final isFragment = words.length <= 2 && trimmed.length <= 25; // Más flexible para fragmentos

    // --- Detección de reinicio de revelado progresivo ---
    // Si recibimos un texto más corto que el actualmente mostrado y es un prefijo del mostrado,
    // lo interpretamos como el controlador iniciando ticks de revelado desde el índice 0.
    // En ese caso NO mostramos esos prefijos regresivos para evitar "reset visual" ni logs [fragment].
    if (_currentAiSubtitle.isNotEmpty &&
        trimmed.length < _currentAiSubtitle.length &&
        _currentAiSubtitle.startsWith(trimmed)) {
      _progressiveRevealActive = true;
      return; // ignorar este tick regresivo
    }

    // Si estamos en modo revelado progresivo: siempre tratar como actualización completa
    if (_progressiveRevealActive) {
      // A partir de que la longitud alcanza o supera lo ya mostrado, reemplazamos directamente.
      if (trimmed.length >= _currentAiSubtitle.length) {
        _accumulatedFragments = ''; // desactivar acumulación de fragmentos
        setState(() => _currentAiSubtitle = trimmed);
        if (_subtitleUiDebug && trimmed.length > _lastLoggedFullLen) {
          _lastLoggedFullLen = trimmed.length;
          debugPrint('👁️ [SUB-UI][full] len=${trimmed.length} -> "$trimmed"');
        }
      }
      return; // no pasar por rama de fragmentos para evitar duplicados
    }

    // debugPrint('[Subtítulo] Recibido: "$text" -> ${isFragment ? "FRAGMENTO" : "COMPLETO"}');

    // Si aún no comenzó el revelado y no hemos recibido sentinel, NO mostrar fragmentos (solo los ignoramos)
    if (isFragment && !_revealStarted) {
      return; // ocultar
    }
    if (isFragment) {
      // Es un fragmento, verificar si ya lo tenemos para evitar duplicados
      // Usar el texto acumulado completo para detectar duplicados más precisamente
      if (_accumulatedFragments.trim().endsWith(trimmed) || _accumulatedFragments.contains('$trimmed ')) {
        // debugPrint('[Subtítulo] Fragmento duplicado ignorado: "$trimmed"');
        return; // Salir sin agregar nada
      }

      // Agregar con espacio inteligente
      if (_accumulatedFragments.isNotEmpty &&
          !_accumulatedFragments.endsWith(' ') &&
          !trimmed.startsWith(' ') &&
          !RegExp(r'^[.,!?;:]').hasMatch(trimmed)) {
        _accumulatedFragments += ' ';
      }
      _accumulatedFragments += trimmed;
      // debugPrint('[Subtítulo] Acumulado: "$_accumulatedFragments"');
      final newText = _accumulatedFragments;
      setState(() => _currentAiSubtitle = newText);
      if (_subtitleUiDebug) {
        // Log completo para poder comparar con revelado del controlador
        debugPrint('👁️ [SUB-UI][fragment] len=${newText.length} added="$trimmed" -> "$newText"');
      }

      // Para fragmentos, cancelar timer previo (si la IA sigue hablando, no limpiar subtítulos)
      // Los fragmentos indican que la IA sigue hablando
      _subtitleTimer?.cancel();
    } else {
      // Es texto completo y fluido, reemplazar todo
      // debugPrint('[Subtítulo] Reemplazando con versión completa: "$text"');
      _accumulatedFragments = ''; // Limpiar acumulación
      String newText = text;
      // Colapsar placeholders de puntos (>=4) que pueden venir de merging previo o modelo.
      if (newText.contains('....')) {
        // Normalizar secuencias largas de puntos a un solo espacio (placeholder eliminado)
        newText = newText.replaceAll(RegExp(r'\.{4,}'), ' ');
        newText = newText.replaceAll(RegExp(r'\s{2,}'), ' ');
      }
      setState(() => _currentAiSubtitle = newText);
      if (_subtitleUiDebug && newText.length > _lastLoggedFullLen) {
        _lastLoggedFullLen = newText.length;
        debugPrint('👁️ [SUB-UI][full] len=${newText.length} -> "$newText"');
      }

      // Solo cuando llega la versión completa programar limpieza
      // con más tiempo (la IA terminó de hablar)
      _subtitleTimer?.cancel();
      _subtitleTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted) return;
        setState(() {
          _currentAiSubtitle = '';
          _accumulatedFragments = ''; // También limpiar la acumulación
        });
        if (_subtitleUiDebug) debugPrint('👁️ [SUB-UI] cleared (timeout)');
      });
    }
  }

  void _showUserSubtitle(String text) {
    if (!mounted || _hideSubtitles) return;

    setState(() => _currentUserSubtitle = text);

    // Auto-hide user subtitle after 8 seconds
    _userSubtitleTimer?.cancel();
    _userSubtitleTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _currentUserSubtitle = '');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    controller = VoiceCallController(openAIService: openai);

    // Cargar voz activa guardada
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final v = prefs.getString('selected_voice');
        if (v != null && mounted) setState(() => _activeVoice = v);
      } catch (_) {}
    });

    // Iniciar llamada
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String systemPrompt;

      try {
        final chat = context.read<ChatProvider>();
        systemPrompt = chat.buildCallSystemPromptJson(maxRecent: 32);
        debugPrint('VoiceCallChat: usando SystemPrompt JSON de llamada (len=${systemPrompt.length})');
      } catch (e) {
        debugPrint('VoiceCallChat: ChatProvider no disponible ($e). Simulando llamada no respondida.');
        if (!mounted) return;
        await controller.playNoAnswerTone(duration: const Duration(seconds: 6));
        if (!mounted) return;
        await _hangUp();
        return;
      }

      if (!mounted) return;

      await controller.startContinuousCall(
        systemPrompt: systemPrompt,
        onText: (chunk) => _showAiSubtitle(chunk),
        onUserTranscription: (transcription) => _showUserSubtitle(transcription),
        onHangupReason: (reason) async {
          if (!mounted) return;
          setState(() => _hideSubtitles = true);

          if (!_hangupNoticeShown) {
            _hangupNoticeShown = true;
            final messenger = ScaffoldMessenger.of(context);
            messenger.clearSnackBars();
            messenger.showSnackBar(
              SnackBar(
                content: const Text(
                  'Llamada colgada automáticamente por política del modelo.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          try {
            unawaited(controller.playHangupTone());
          } catch (_) {}
          await _hangUp();
        },
        recorder: _recorder,
        model: 'gpt-4o-mini-realtime',
      );

      // Ensure microphone is unmuted after starting call
      controller.setMuted(false);
    });

    // Escuchar nivel normalizado del micrófono
    try {
      _levelSub = controller.micLevelStream.listen((level) {
        final l = (level.isNaN ? 0.0 : level).clamp(0.0, 1.0);
        _soundLevel = (_soundLevel * 0.6) + (l * 0.4);
        if (mounted) setState(() {});
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _subtitleTimer?.cancel();
    _userSubtitleTimer?.cancel();
    try {
      _levelSub?.cancel();
    } catch (_) {}
    _controller.dispose();
    controller.stop();
    super.dispose();
  }

  late AnimationController _controller;
  double _soundLevel = 0.0;
  String? _activeVoice;

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.cyanAccent;
    final accentColor = Colors.pinkAccent;
    final voices = const ['alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'];
    final activeVoice = _activeVoice;
    final neonShadow = [
      BoxShadow(color: baseColor.withAlpha((0.7 * 255).round()), blurRadius: 16, spreadRadius: 2),
      BoxShadow(color: accentColor.withAlpha((0.4 * 255).round()), blurRadius: 32, spreadRadius: 8),
    ];

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _hangUp();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: Row(
            children: [
              Icon(Icons.phone_in_talk, color: accentColor, size: 28),
              const SizedBox(width: 8),
              Text(
                'AI-Chan',
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 1.2,
                  shadows: [Shadow(color: accentColor.withAlpha((0.5 * 255).round()), blurRadius: 8)],
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Voz',
              icon: const Icon(Icons.record_voice_over, color: Colors.cyanAccent),
              color: Colors.black,
              onSelected: (v) {
                controller.setVoice(v);
                () async {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('selected_voice', v);
                    if (mounted) setState(() => _activeVoice = v);
                  } catch (_) {
                    if (mounted) setState(() => _activeVoice = v);
                  }
                }();
              },
              itemBuilder: (context) => [
                for (final v in voices)
                  PopupMenuItem<String>(
                    value: v,
                    child: Row(
                      children: [
                        Icon(
                          activeVoice == v ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 18,
                          color: Colors.cyanAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(v, style: const TextStyle(color: Colors.cyanAccent)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CyberpunkGlowPainter(baseColor: baseColor, accentColor: accentColor),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 40.0),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: WavePainter(
                              animation: _controller.value,
                              soundLevel: _soundLevel,
                              baseColor: baseColor,
                              accentColor: accentColor,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: neonShadow,
                          border: Border.all(color: accentColor, width: 3),
                          gradient: RadialGradient(
                            colors: [
                              Colors.black,
                              accentColor.withAlpha((0.15 * 255).round()),
                              baseColor.withAlpha((0.10 * 255).round()),
                            ],
                            stops: const [0.7, 0.9, 1.0],
                          ),
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Icon(
                          Icons.mic_none,
                          color: accentColor,
                          size: 64,
                          shadows: [Shadow(color: baseColor.withAlpha((0.7 * 255).round()), blurRadius: 16)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Subtítulo IA actual
            if (!_hideSubtitles && _currentAiSubtitle.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 110 + 72 + 8,
                child: _ScrollableAiSubtitle(text: _currentAiSubtitle),
              ),
            // Subtítulo usuario actual
            if (!_hideSubtitles && _currentUserSubtitle.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 110 + 72 + 8 + 70,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      _currentUserSubtitle,
                      style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute/Unmute
                  GestureDetector(
                    onTap: () {
                      setState(() => _muted = !_muted);
                      controller.setMuted(_muted);
                    },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor, width: 3),
                        color: _muted ? Colors.grey.shade800 : Colors.transparent,
                      ),
                      child: Icon(_muted ? Icons.mic_off : Icons.mic, color: accentColor, size: 36),
                    ),
                  ),
                  // Colgar
                  GestureDetector(
                    onTap: () async {
                      controller.setMuted(true);
                      await _hangUp();
                    },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Colors.redAccent.shade700, accentColor.withAlpha((0.7 * 255).round())],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withAlpha((0.7 * 255).round()),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                          BoxShadow(color: accentColor.withAlpha((0.2 * 255).round()), blurRadius: 32, spreadRadius: 8),
                        ],
                        border: Border.all(color: accentColor, width: 2.5),
                      ),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 38),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableAiSubtitle extends StatefulWidget {
  final String text;
  const _ScrollableAiSubtitle({required this.text});

  @override
  State<_ScrollableAiSubtitle> createState() => _ScrollableAiSubtitleState();
}

class _ScrollableAiSubtitleState extends State<_ScrollableAiSubtitle> {
  final _scrollCtrl = ScrollController();
  String _lastText = '';
  @override
  void didUpdateWidget(covariant _ScrollableAiSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Autoscroll al final siempre
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final changed = text != _lastText;
    if (changed) _lastText = text;
    return Container(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 170),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha((0.35 * 255).round()),
        border: Border.all(color: Colors.cyanAccent.withAlpha((0.4 * 255).round())),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.cyanAccent.withAlpha((0.2 * 255).round()), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Scrollbar(
        controller: _scrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.only(right: 4),
          child: CyberpunkRealtimeSubtitle(
            text: text,
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w400, height: 1.25),
          ),
        ),
      ),
    );
  }
}

extension _CallSummary on _VoiceCallChatState {
  Future<void> _saveCallSummaryIfAny(ChatProvider? chat) async {
    try {
      debugPrint('[AI-chan][VoiceCall] Iniciando proceso de resumen...');

      // Usar el nuevo método del controller para crear el resumen
      final callSummary = controller.createCallSummary();

      debugPrint('[AI-chan][VoiceCall] CallSummary creado: true');
      debugPrint('[AI-chan][VoiceCall] - Duración: ${callSummary.duration}');
      debugPrint('[AI-chan][VoiceCall] - User habló: ${callSummary.userSpoke}');
      debugPrint('[AI-chan][VoiceCall] - AI respondió: ${callSummary.aiResponded}');
      debugPrint('[AI-chan][VoiceCall] - Mensajes: ${callSummary.messages.length}');

      if (chat != null) {
        // Verificar si vale la pena generar resumen
        if (!callSummary.userSpoke) {
          debugPrint('[AI-chan][VoiceCall] ⏭️ Usuario no habló - no se generará resumen');
        } else if (callSummary.messages.isEmpty) {
          debugPrint('[AI-chan][VoiceCall] ⏭️ Sin mensajes - no se generará resumen');
        } else if (callSummary.duration.inSeconds < 5) {
          debugPrint(
            '[AI-chan][VoiceCall] ⏭️ Llamada muy corta (${callSummary.duration.inSeconds}s) - no se generará resumen',
          );
        } else {
          debugPrint('[AI-chan][VoiceCall] Generando resumen de texto...');

          // Usar el servicio dedicado para generar resumen
          final summaryService = VoiceCallSummaryService(profile: chat.onboardingData);
          final conversationSummary = await summaryService.generateSummaryText(callSummary);

          debugPrint('[AI-chan][VoiceCall] Resumen generado (${conversationSummary.length} chars)');

          // Solo guardar si hay contenido útil en el resumen
          if (conversationSummary.isNotEmpty) {
            debugPrint('[AI-chan][VoiceCall] Guardando call summary como mensaje del usuario');

            // Crear mensaje con campos de llamada pero solo con el resumen como texto
            final callMessage = Message(
              text: conversationSummary,
              sender: MessageSender.user,
              dateTime: callSummary.startTime,
              callDuration: callSummary.duration,
              callEndTime: callSummary.endTime,
              status: MessageStatus.read,
            );

            await chat.addUserMessage(callMessage);
            debugPrint('[AI-chan][VoiceCall] ✅ Mensaje de resumen guardado exitosamente');
          } else {
            debugPrint('[AI-chan][VoiceCall] ⏭️ Resumen vacío - no se guardará mensaje de llamada');
          }
        }
      } else {
        debugPrint('[AI-chan][VoiceCall] ❌ No hay chat disponible para guardar resumen');
      }

      // Limpiar mensajes del controller
      controller.clearMessages();
    } catch (e, stackTrace) {
      debugPrint('[AI-chan][VoiceCall] ❌ Error guardando resumen: $e');
      debugPrint('[AI-chan][VoiceCall] Stack trace: $stackTrace');
    }
  }
}
