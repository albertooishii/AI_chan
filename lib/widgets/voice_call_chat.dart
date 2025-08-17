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
  final bool incoming; // true si la llamada es entrante (IA llama al usuario)
  const VoiceCallChat({super.key, this.incoming = false});

  @override
  State<VoiceCallChat> createState() => _VoiceCallChatState();
}

class _VoiceCallChatState extends State<VoiceCallChat> with SingleTickerProviderStateMixin {
  bool _hangupInProgress = false;
  bool _hangupNoticeShown = false;
  bool _incomingAccepted = false; // para distinguir si se respondió
  bool _endCallTagHandled = false; // si la IA emitió [end_call][/end_call]
  bool _forceReject = false; // forzar ruta de rechazo (IA rechazó con etiqueta)
  bool _startCallTagReceived = false; // si IA aceptó con [start_call][/start_call]
  bool _implicitRejectHandled = false; // rechazo implícito por texto largo inicial
  int _earlyPhaseAlnumAccumulated = 0; // acumulador de caracteres alfanuméricos en fase temprana para rechazo implícito
  Timer? _noAnswerTimer; // timeout para llamada no contestada
  Timer? _incomingAnswerTimer; // timeout para llamadas entrantes no aceptadas
  // Debug UI subtítulos
  final bool _subtitleUiDebug = true; // ACTIVADO: mostrar logs detallados de subtítulos

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

    // Determinar si hubo conversación (usuario o IA habló) antes de limpiar
    final bool hadConversation = controller.userSpokeFlag || controller.aiRespondedFlag;
    final int? placeholderIndex = chat?.pendingIncomingCallMsgIndex;
    // Forzar rechazo si IA emitió [end_call][/end_call] (aunque controller marque que habló)
    // Nuevo criterio: "aceptación silenciosa" => hubo (start_call) pero jamás llegó audio ni voz usuario -> tratar como rechazo técnico
    final bool silentAcceptance =
        _startCallTagReceived && !controller.firstAudioReceivedFlag && !controller.userSpokeFlag;
    // Reglas actualización:
    // - Rejected: usuario/IA explicitó rechazo (_forceReject) o IA aceptó start_call pero nunca hubo audio ni voz (silentAcceptance)
    // - Missed: no hubo conversación (nadie habló) y no se recibió etiqueta de fin [end_call][/end_call] (llamada sin contestar)
    bool markRejected = _forceReject || silentAcceptance;
    bool markMissed = false;
    if (!markRejected && !hadConversation) {
      // Llamada perdida (sin respuesta) si había placeholder entrante o saliente sin interacción
      markMissed = true;
    }
    // Si antes marcábamos como rejected por placeholder pendiente sin conversación, ahora lo reinterpretamos como missed
    final bool shouldMarkRejected = markRejected;

    // Limpieza en background: detener sesión de voz/mic y guardar resumen o marcar rechazo
    unawaited(
      _performBackgroundCleanup(
        chat,
        markRejected: shouldMarkRejected,
        markMissed: markMissed,
        placeholderIndex: placeholderIndex,
      ),
    );
  }

  Future<void> _performBackgroundCleanup(
    ChatProvider? chat, {
    bool markRejected = false,
    bool markMissed = false,
    int? placeholderIndex,
    String? rejectionText,
  }) async {
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

    if (chat != null) {
      if (markRejected) {
        debugPrint('🧹 Marcando llamada rechazada (flag markRejected=true)');
        try {
          if (placeholderIndex != null) {
            chat.rejectIncomingCallPlaceholder(index: placeholderIndex, text: rejectionText ?? 'Llamada rechazada');
          } else {
            // Llamada saliente rechazada / no contestada (no hay placeholder entrante)
            await chat.updateOrAddCallStatusMessage(
              text: rejectionText ?? 'Llamada rechazada',
              callStatus: CallStatus.rejected,
              incoming: widget.incoming,
              placeholderIndex: chat.pendingIncomingCallMsgIndex,
            );
          }
        } catch (e) {
          debugPrint('[AI-chan][VoiceCall] Error marcando rechazo: $e');
        }
      } else if (markMissed) {
        debugPrint('🧹 Marcando llamada perdida (missed)');
        try {
          if (placeholderIndex != null) {
            // Reemplazar placeholder entrante con estado missed
            chat.rejectIncomingCallPlaceholder(index: placeholderIndex, text: 'Llamada sin contestar');
          } else {
            await chat.updateOrAddCallStatusMessage(
              text: 'Llamada sin contestar',
              callStatus: CallStatus.missed,
              incoming: widget.incoming,
              placeholderIndex: chat.pendingIncomingCallMsgIndex,
            );
          }
        } catch (e) {
          debugPrint('[AI-chan][VoiceCall] Error marcando missed: $e');
        }
      } else {
        try {
          debugPrint('🧹 Guardando resumen de llamada...');
          final summaryResult = await _generateCallSummary(chat);
          if (summaryResult != null) {
            final (callSummary, summaryText) = summaryResult;
            if (widget.incoming && chat.pendingIncomingCallMsgIndex != null) {
              chat.replaceIncomingCallPlaceholder(
                index: chat.pendingIncomingCallMsgIndex!,
                summary: callSummary,
                summaryText: summaryText,
              );
            } else {
              final callMessage = Message(
                text: summaryText,
                sender: MessageSender.user,
                dateTime: callSummary.startTime,
                callDuration: callSummary.duration,
                callEndTime: callSummary.endTime,
                status: MessageStatus.read,
                callStatus: CallStatus.completed,
              );
              await chat.addUserMessage(callMessage);
            }
            debugPrint('🧹 Proceso de resumen completado');
          } else {
            debugPrint('🧹 No se generó resumen (criterios no cumplidos)');
            // Política solicitada:
            // 1. Si fue rechazo (markRejected ya tratado arriba) y llegamos aquí sin summary -> mostrar "Llamada rechazada".
            // 2. Si usuario colgó muy temprano (sin start_call, sin audio IA, sin voz usuario) -> NO registrar nada.
            // 3. Otros casos (llamada muy corta aceptada) -> por ahora no registrar.
            final earlyAbort =
                !_startCallTagReceived &&
                !controller.firstAudioReceivedFlag &&
                !controller.userSpokeFlag &&
                !_endCallTagHandled;
            if (earlyAbort) {
              debugPrint('🧹 Colgado temprano sin respuesta -> sin registro de mensaje.');
            } else if (markRejected) {
              try {
                debugPrint(
                  '[RejectFlow] markRejected path: incoming=${widget.incoming} placeholderIndex=${chat.pendingIncomingCallMsgIndex} totalMsgsBefore=${chat.messages.length}',
                );
                if (widget.incoming && chat.pendingIncomingCallMsgIndex != null) {
                  chat.rejectIncomingCallPlaceholder(
                    index: chat.pendingIncomingCallMsgIndex!,
                    text: 'Llamada rechazada',
                  );
                  debugPrint('[RejectFlow] Placeholder reemplazado -> totalMsgsAfter=${chat.messages.length}');
                } else {
                  // Crear mensaje con sender apropiado (assistant si era entrante, user si saliente)
                  await chat.updateOrAddCallStatusMessage(
                    text: 'Llamada rechazada',
                    callStatus: CallStatus.rejected,
                    incoming: widget.incoming,
                    placeholderIndex: null,
                  );
                  debugPrint('[RejectFlow] Mensaje añadido -> totalMsgsAfter=${chat.messages.length}');
                }
                debugPrint('🧹 Registrado mensaje de llamada rechazada (sin resumen)');
              } catch (e) {
                debugPrint('⚠️ Error registrando llamada rechazada sin resumen: $e');
              }
            } else if (markMissed) {
              try {
                debugPrint('[MissedFlow] Registrando llamada sin contestar');
                await chat.updateOrAddCallStatusMessage(
                  text: 'Llamada sin contestar',
                  callStatus: CallStatus.missed,
                  incoming: widget.incoming,
                  placeholderIndex: null,
                );
              } catch (e) {
                debugPrint('⚠️ Error registrando llamada missed: $e');
              }
            } else {
              debugPrint('🧹 Llamada corta aceptada sin resumen -> no se registra mensaje.');
            }
          }
        } catch (e) {
          debugPrint('🧹 Error guardando resumen: $e');
        }
      }
    }
    debugPrint('🧹 Limpieza en background finalizada');
  }

  Future<void> _hangUpNoAnswer() async {
    // Reutiliza misma lógica de _hangUp, marcando rechazo/no contestada
    if (_hangupInProgress) return;
    _forceReject = true; // marcar para que background cleanup lo trate como rechazo
    await _hangUp();
  }

  // Sistema de subtítulos con concatenación
  String _currentAiSubtitle = '';
  String _accumulatedFragments = ''; // Acumular fragmentos hasta tener frase completa
  String _currentUserSubtitle = ''; // Subtítulos del usuario
  bool _hideSubtitles = false;
  Timer? _subtitleTimer;
  Timer? _userSubtitleTimer;
  // Logging y control simple
  String _lastLoggedSubtitle = ''; // para delta logging
  int _rawSubtitleSeq = 0; // contador de textos crudos recibidos

  // --- FIN: eliminación de lógica progresiva y normalizaciones agresivas para modo ultra simple ---

  // Heurística para limpiar fragmentos degradados (artefactos de streaming parcial)
  // (Funciones de limpieza avanzadas eliminadas para depuración simple)

  void _debugLogDelta(String phase, String nextText) {
    if (!_subtitleUiDebug) return;
    final prev = _lastLoggedSubtitle;
    if (prev == nextText) return;
    // Detectar añadido o recorte
    int commonPrefix = 0;
    final minLen = prev.length < nextText.length ? prev.length : nextText.length;
    while (commonPrefix < minLen && prev.codeUnitAt(commonPrefix) == nextText.codeUnitAt(commonPrefix)) {
      commonPrefix++;
    }
    final removed = prev.length > commonPrefix ? prev.substring(commonPrefix) : '';
    final added = nextText.length > commonPrefix ? nextText.substring(commonPrefix) : '';
    debugPrint(
      '👁️ [SUB-Δ][$phase] len=${nextText.length} +' +
          added.length.toString() +
          '/-' +
          removed.length.toString() +
          (removed.isNotEmpty ? ' removed="${_shorten(removed)}"' : '') +
          (added.isNotEmpty ? ' added="${_shorten(added)}"' : '') +
          ' -> "${_shorten(nextText, 160)}"',
    );
    _lastLoggedSubtitle = nextText;
  }

  String _shorten(String s, [int max = 60]) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '…';
  }

  // Eliminadas funciones de recorte/deduplicación complejas

  final OpenAIService openai = OpenAIService();
  late final VoiceCallController controller;
  final AudioRecorder _recorder = AudioRecorder();
  bool _muted = false;
  StreamSubscription<double>? _levelSub;

  Future<(VoiceCallSummary, String)?> _generateCallSummary(ChatProvider? chat) async {
    try {
      final callSummary = controller.createCallSummary();
      if (chat == null) return null;
      if (!callSummary.userSpoke) return null;
      if (callSummary.messages.isEmpty) return null;
      if (callSummary.duration.inSeconds < 5) return null;
      final summaryService = VoiceCallSummaryService(profile: chat.onboardingData);
      final conversationSummary = await summaryService.generateSummaryText(callSummary);
      if (conversationSummary.isEmpty) return null;
      controller.clearMessages();
      return (callSummary, conversationSummary);
    } catch (e) {
      debugPrint('[AI-chan][VoiceCall] Error generando resumen: $e');
      return null;
    }
  }

  void _showAiSubtitle(String text) {
    if (!mounted || _hideSubtitles) return;

    // Log crudo siempre
    _rawSubtitleSeq++;
    if (_subtitleUiDebug) {
      debugPrint('👁️ [RAW-SUB][#$_rawSubtitleSeq] len=${text.length} -> "$text"');
    }

    // Ignorar sentinel antiguo de revelado
    if (text == '__REVEAL__') return;

    // Gating: no mostrar nada antes del primer audio IA real
    if (!controller.firstAudioReceivedFlag) return;

    // Supresión global (rechazo / end_call)
    try {
      if (controller.suppressFurtherAiTextFlag) return;
    } catch (_) {}

    final raw = text.trim();
    if (raw.isEmpty) return;

    // Ignorar retrocesos (prefijo más corto)
    if (_currentAiSubtitle.isNotEmpty && raw.length < _currentAiSubtitle.length && _currentAiSubtitle.startsWith(raw)) {
      return;
    }

    // Normalización mínima: colapsar espacios, unir '¡ ' / '¿ '
    String cleaned = raw.replaceAll(RegExp(r'\s{2,}'), ' ');
    cleaned = cleaned.replaceAllMapped(RegExp(r'([¡¿])\s+([A-Za-zÁÉÍÓÚáéíóúÑñ])'), (m) => '${m.group(1)}${m.group(2)}');

    // Política simple de actualización: actualizar si crece o termina en puntuación fuerte
    final grows = cleaned.length >= _currentAiSubtitle.length;
    final punctFinish = RegExp(r'[\.\!\?…]$').hasMatch(cleaned);
    if (!grows && !punctFinish) return;

    if (cleaned != _currentAiSubtitle) {
      setState(() => _currentAiSubtitle = cleaned);
      _debugLogDelta('simple', cleaned);
    }

    // Programar limpieza diferida (reiniciar cada update)
    _subtitleTimer?.cancel();
    _subtitleTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() => _currentAiSubtitle = '');
      if (_subtitleUiDebug) debugPrint('👁️ [SUB-UI] cleared (timeout)');
    });
  }

  // Eliminadas heurísticas de reinicio y comparación de palabras

  void _showUserSubtitle(String text) {
    if (!mounted || _hideSubtitles) return;

    // Filtro de frases inválidas / watermarks / artefactos que NO deben mostrarse como subtítulo del usuario
    // Ejemplo reportado: "Subtítulos realizados por la comunidad de Amara.org" (o variantes)
    try {
      final raw = text.trim();
      if (raw.isNotEmpty) {
        final lower = raw.toLowerCase();
        // Lista de frases / patrones prohibidos (extensible)
        final blockedSubstrings = <String>[
          'subtítulos realizados por la comunidad de amara.org',
          // variantes sin acento o con posibles errores del ASR
          'subtitulos realizados por la comunidad de amara.org',
        ];
        final blockedRegexes = <RegExp>[
          // tolera í o i, posibles espacios extra
          RegExp(r'subt[íi]tulos\s+realizados\s+por\s+la\s+comunidad\s+de\s+amara\.org', caseSensitive: false),
        ];
        bool blocked = blockedSubstrings.any((p) => lower.contains(p)) || blockedRegexes.any((r) => r.hasMatch(raw));
        // También bloquear si empieza con nuestro prefijo de log accidental
        if (!blocked && lower.startsWith('🎤 user transcription received')) blocked = true;
        if (blocked) {
          if (_subtitleUiDebug) {
            debugPrint('👁️ [SUB-UI][user] suprimido watermark/artefacto: "$raw"');
          }
          return; // no mostrar
        }
      }
    } catch (_) {
      // Silencioso: en caso de error de parsing, seguimos mostrando texto normal.
    }

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

    // Llamada saliente: iniciar inmediatamente. Entrante: esperar a que usuario acepte.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.incoming) {
        await _startCallInternal();
      } else {
        // Ring entrante continuo (loop) hasta aceptar / colgar
        await controller.startIncomingRing();
        // Programar timeout de no contestar (usuario no acepta la llamada entrante).
        _incomingAnswerTimer?.cancel();
        _incomingAnswerTimer = Timer(const Duration(seconds: 10), () async {
          if (mounted && !_incomingAccepted && !_hangupInProgress) {
            debugPrint('[AI-chan][VoiceCall] Timeout entrante 10s sin aceptar -> marcar no contestada');
            ChatProvider? chat;
            try {
              chat = context.read<ChatProvider>();
            } catch (_) {}
            try {
              await controller.stopIncomingRing();
            } catch (_) {}
            // Rechazar placeholder si existe
            if (chat?.pendingIncomingCallMsgIndex != null) {
              try {
                chat!.rejectIncomingCallPlaceholder(
                  index: chat.pendingIncomingCallMsgIndex!,
                  text: 'Llamada no contestada',
                );
              } catch (e) {
                debugPrint('[AI-chan][VoiceCall] Error marcando no contestada entrante: $e');
              }
            } else {
              try {
                await chat?.updateOrAddCallStatusMessage(
                  text: 'Llamada no contestada',
                  callStatus: CallStatus.missed,
                  incoming: widget.incoming,
                  placeholderIndex: chat.pendingIncomingCallMsgIndex,
                );
              } catch (_) {}
            }
            if (mounted) {
              try {
                Navigator.of(context).maybePop();
              } catch (_) {}
            }
          }
        });
      }
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
    _incomingAnswerTimer?.cancel();
    _noAnswerTimer?.cancel();
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
    final isIncoming = widget.incoming;
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
                isIncoming ? 'Llamada entrante' : 'AI-Chan',
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
            // Controles inferiores (añadir botón aceptar en entrante)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (isIncoming && !_incomingAccepted) ...[
                    // Botón aceptar
                    GestureDetector(
                      onTap: () async {
                        // Capturar provider antes de cualquier await para evitar warning de context tras async gap
                        // Ya no necesitamos capturar el provider aquí; mantenemos el índice para reemplazo posterior.
                        await controller.stopIncomingRing();
                        _incomingAccepted = true;
                        if (mounted) setState(() {});
                        await _startCallInternal();
                        // NOTA: No limpiamos pendingIncomingCallMsgIndex aquí.
                        // Debe mantenerse hasta que el resumen reemplace el placeholder
                        // para conservar el sender=assistant y mostrar "Llamada recibida".
                        // Se limpiará en replaceIncomingCallPlaceholder().
                      },
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.greenAccent.shade400, baseColor.withAlpha((0.6 * 255).round())],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.greenAccent.withAlpha((0.7 * 255).round()),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                          border: Border.all(color: baseColor, width: 2.5),
                        ),
                        child: const Icon(Icons.call, color: Colors.white, size: 38),
                      ),
                    ),
                  ],
                  // Mute/Unmute (oculto mientras llamada entrante no aceptada)
                  if (!isIncoming || _incomingAccepted)
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
                      if (widget.incoming && !_incomingAccepted) {
                        // Rechazo: parar ring
                        await controller.stopIncomingRing();
                      }
                      controller.setMuted(true);
                      // Asegurar detener ringback (saliente o entrante) al colgar
                      try {
                        await controller.stopRingback();
                      } catch (_) {}
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

extension _IncomingLogic on _VoiceCallChatState {
  Future<void> _startCallInternal() async {
    String systemPrompt;
    try {
      final chat = context.read<ChatProvider>();
      systemPrompt = chat.buildCallSystemPromptJson(
        maxRecent: 32,
        aiInitiatedCall: widget.incoming, // incoming=true => IA inició la llamada
      );
      debugPrint('VoiceCallChat: usando SystemPrompt JSON de llamada (len=${systemPrompt.length})');
    } catch (e) {
      debugPrint('VoiceCallChat: ChatProvider no disponible ($e).');
      if (!mounted) return;
      await controller.playNoAnswerTone(duration: const Duration(seconds: 3));
      if (!mounted) return;
      await _hangUp();
      return;
    }

    if (!mounted) return;
    await controller.startContinuousCall(
      systemPrompt: systemPrompt,
      onText: (chunk) {
        // Detección temprana de etiqueta de rechazo IA
        if (!_endCallTagHandled) {
          final trimmed = chunk.trim();

          // Detección adicional: modelo dijo verbalmente "end call" sin corchetes (p.ej. lo leyó en voz)
          // Solo lo tomamos como rechazo si ocurre al inicio (antes de conversación) y viene solo.
          // Regex robusta para 'end call' con posibles espacios, guion bajo, puntuación, comillas o paréntesis
          final plainEndCall = RegExp(
            r'^["“”\(\[\{\s]*end[ _]call[\.\!\?\s\]\}\)"“”]*$',
            caseSensitive: false,
          ).hasMatch(trimmed);
          if (plainEndCall) {
            final earlyPlain = !_startCallTagReceived && !controller.userSpokeFlag && !controller.aiRespondedFlag;
            debugPrint(
              '[AI-chan][VoiceCall] Detectado "end call" plano (voz) early=$earlyPlain -> colgando silencioso',
            );
            controller.suppressFurtherAiText();
            _currentAiSubtitle = '';
            _accumulatedFragments = '';
            _endCallTagHandled = true;
            if (earlyPlain) _forceReject = true; // si es temprano lo marcamos como rechazo
            () async {
              try {
                controller.setMuted(true);
                await controller.stopRingback();
                controller.discardPendingAiAudio();
                await controller.stopCurrentAiPlayback();
              } catch (_) {}
              await _hangUp();
            }();
            return;
          }

          // --- Detección tolerante de start_call ---
          // Formas aceptadas puras (activan aceptación): [start_call], [start_call][/start_call], [/start_call]
          final isPureStartTag =
              trimmed == '[start_call][/start_call]' || trimmed == '[start_call]' || trimmed == '[/start_call]';
          final containsAnyStart =
              chunk.contains('[start_call]') ||
              chunk.contains('[start_call][/start_call]') ||
              chunk.contains('[/start_call]');

          if (containsAnyStart) {
            if (isPureStartTag) {
              // Solo aceptar si es etiqueta "pura" sin texto adicional alrededor.
              if (!_startCallTagReceived) {
                _startCallTagReceived = true;
                debugPrint('[AI-chan][VoiceCall] Detectado start_call puro (aceptación)');
                // Ya no detenemos el ringback aquí; se detendrá automáticamente al primer audio IA.
                _noAnswerTimer?.cancel();
                _incomingAnswerTimer?.cancel();
                try {
                  controller.requestImmediateAudioResponse(includeText: true);
                } catch (_) {}
              }
              return; // No mostrar etiqueta pura
            } else {
              // Etiqueta start_call acompañada de texto: se IGNORA TODO ese texto (no subtítulo, no log conversational)
              controller.discardAiTextIfStartCallArtifact();
              // Limpiar cualquier subtítulo AI ya mostrado (fragmentos previos) para asegurar que nada del texto contaminado quede visible
              if (mounted) {
                _currentAiSubtitle = '';
                _accumulatedFragments = '';
                // Usar setState para reflejar limpieza inmediata
                // ignore: invalid_use_of_protected_member
                setState(() {});
              }
              if (!_startCallTagReceived) {
                // Tratarlo igualmente como aceptación salvage
                _startCallTagReceived = true;
                debugPrint('[AI-chan][VoiceCall] Salvage: start_call contaminado -> aceptación forzada');
                // Mantener ringback hasta primer audio IA (no detener todavía)
                _noAnswerTimer?.cancel();
                _incomingAnswerTimer?.cancel();
                // Pedir audio aunque la respuesta inicial siga activa
                controller.salvageStartCallAfterContaminatedTag();
              }
              return; // no mostrar nada
            }
          }

          // --- Detección tolerante de end_call ---
          // Formas aceptadas para colgar: [end_call][/end_call], [end_call], [/end_call]
          final isPureEndTag =
              trimmed == '[end_call][/end_call]' || trimmed == '[end_call]' || trimmed == '[/end_call]';
          final containsEndTag =
              isPureEndTag ||
              chunk.contains('[end_call][/end_call]') ||
              chunk.contains('[end_call]') ||
              chunk.contains('[/end_call]');
          if (containsEndTag) {
            _endCallTagHandled = true;
            controller.suppressFurtherAiText();
            _currentAiSubtitle = '';
            _accumulatedFragments = '';
            // Cortar audio IA ya en reproducción para que no se oiga "end_call" pronunciado
            () async {
              try {
                await controller.stopCurrentAiPlayback();
              } catch (_) {}
            }();
            // Fase temprana: no hubo start_call aceptado, ni audio IA, ni voz usuario.
            final earlyPhase =
                !_startCallTagReceived && !controller.firstAudioReceivedFlag && !controller.userSpokeFlag;
            // Considerar que hubo conversación solo si realmente hubo audio IA o voz usuario (texto puro no cuenta)
            final realConversation = controller.userSpokeFlag || controller.firstAudioReceivedFlag;
            _forceReject = earlyPhase || !realConversation; // rechazo si fue antes de audio/voz real
            debugPrint(
              '[AI-chan][VoiceCall] Detectado [end_call][/end_call] — earlyPhase=$earlyPhase realConversation=$realConversation -> forceReject=$_forceReject',
            );
            // Colgar inmediatamente (limpieza generará mensaje de rechazo)
            // Silenciar y parar ringback si aplica
            () async {
              try {
                controller.setMuted(true);
                await controller.stopRingback();
              } catch (_) {}
              await _hangUp();
            }();
            return; // no mostrar subtítulo
          }

          // Rechazo implícito extendido: si aún no hay start_call ni audio ni habla usuario y llega texto sustancial
          // (sin ninguna etiqueta) lo tratamos como rechazo y colgamos. Evita que se muestre en subtítulos.
          final noTags = !chunk.contains('[start_call') && !chunk.contains('[end_call');
          final earlyPhase =
              !_startCallTagReceived &&
              !_endCallTagHandled &&
              !controller.firstAudioReceivedFlag &&
              !controller.userSpokeFlag;
          if (noTags && earlyPhase && !_implicitRejectHandled) {
            final cleaned = trimmed.replaceAll(RegExp(r'\s+'), ' ');
            // Considerar "sustancial" si supera 6 caracteres alfanuméricos (evitar respirar, etc.)
            final alnumLen = cleaned.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚáéíóúÑñ0-9]'), '').length;
            // Acumular longitud alfanumérica temprana (algunos modelos emiten en fragmentos muy cortos)
            _earlyPhaseAlnumAccumulated += alnumLen;
            final totalEarly = _earlyPhaseAlnumAccumulated;
            // Umbral combinado: >6 en un fragmento O >10 acumulado (robusto a fragmentación)
            if (alnumLen > 6 || totalEarly > 10) {
              _implicitRejectHandled = true;
              _endCallTagHandled = true; // tratar como end_call
              _forceReject = true;
              debugPrint('[AI-chan][VoiceCall] Rechazo implícito: texto inicial sin protocolo -> colgando');
              // Limpiar cualquier fragmento que haya entrado parcialmente
              _currentAiSubtitle = '';
              _accumulatedFragments = '';
              controller.suppressFurtherAiText();
              () async {
                try {
                  controller.setMuted(true);
                  await controller.stopRingback();
                } catch (_) {}
                await _hangUp();
              }();
              return; // no mostrar subtítulo
            }
          }
        }
        // No mostrar subtítulos si controller indicó supresión tras end_call / rechazo
        if (controller.suppressFurtherAiTextFlag) {
          if (_currentAiSubtitle.isNotEmpty || _accumulatedFragments.isNotEmpty) {
            _currentAiSubtitle = '';
            _accumulatedFragments = '';
            // ignore: invalid_use_of_protected_member
            setState(() {});
          }
          return;
        }
        _showAiSubtitle(chunk);
      },
      onUserTranscription: (transcription) => _showUserSubtitle(transcription),
      onHangupReason: (reason) async {
        if (!mounted) return;
        // Capturar messenger antes de cualquier await para cumplir regla use_build_context_synchronously
        final messenger = ScaffoldMessenger.maybeOf(context);
        _hideSubtitles = true; // ocultar subtítulos inmediatamente
        if (!_hangupNoticeShown && messenger != null) {
          _hangupNoticeShown = true;
          String msg;
          Color color;
          switch (reason) {
            case 'policy_violation':
              msg = 'Fin: contenido bloqueado por política.';
              color = Colors.redAccent;
              break;
            case 'rate_limit':
              msg = 'Fin: límite de peticiones alcanzado.';
              color = Colors.deepOrangeAccent;
              break;
            case 'model_server_error':
              msg = 'Fin: error interno del modelo.';
              color = Colors.orangeAccent;
              break;
            case 'connection_error':
              msg = 'Fin: problema de conexión.';
              color = Colors.amberAccent;
              break;
            case 'error_model_response':
              msg = 'Fin: fallo al generar respuesta.';
              color = Colors.orangeAccent;
              break;
            default:
              msg = 'Llamada finalizada.';
              color = Colors.grey;
          }
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  msg,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: color,
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
        try {
          unawaited(controller.playHangupTone());
        } catch (_) {}
        await _hangUp();
      },
      onRetryScheduled: (attempt, backoffMs) {
        // Extender timeout de no contestada en salientes si aún no hubo audio ni voz user
        if (!widget.incoming &&
            !_endCallTagHandled &&
            !controller.firstAudioReceivedFlag &&
            !controller.userSpokeFlag) {
          // Extender hasta un máximo de 25s total
          final elapsed = DateTime.now().difference(controller.callStartTime ?? DateTime.now()).inSeconds;
          final remaining = 25 - elapsed;
          if (remaining > 0) {
            _noAnswerTimer?.cancel();
            _noAnswerTimer = Timer(Duration(seconds: remaining), () {
              if (!mounted) return;
              final hasAudio = controller.firstAudioReceivedFlag;
              final userSpoke = controller.userSpokeFlag;
              final answered = (hasAudio || userSpoke) && !_endCallTagHandled;
              if (!answered && !_endCallTagHandled) {
                debugPrint('[AI-chan][VoiceCall] Timeout extendido -> no contestada');
                _hangUpNoAnswer();
              }
            });
            debugPrint(
              '[AI-chan][VoiceCall] Timeout no-answer extendido tras retry intento=$attempt rest=${remaining}s',
            );
          }
        }
      },
      recorder: _recorder,
      model: 'gpt-4o-mini-realtime',
      // Si es entrante pero ya fue aceptada, permitir arranque inicial (no suprimir)
      suppressInitialAiRequest: widget.incoming && !_incomingAccepted,
      playRingback: !widget.incoming, // si era entrante ya sonó antes aceptar
    );
    controller.setMuted(false);

    // Programar timeout de no respuesta (solo en llamadas salientes: usuario llamó a la IA => widget.incoming == false)
    if (!widget.incoming) {
      _noAnswerTimer?.cancel();
      _noAnswerTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        // Nuevo criterio: debe haber audio AI (primer audio) o habla usuario; un start_call sin audio no cuenta.
        final hasAudio = controller.firstAudioReceivedFlag;
        final userSpoke = controller.userSpokeFlag;
        final answered = (hasAudio || userSpoke) && !_endCallTagHandled;
        if (!answered && !_endCallTagHandled) {
          debugPrint('[AI-chan][VoiceCall] Timeout 10s -> no contestada (sin audio IA y sin voz usuario)');
          _hangUpNoAnswer();
        } else {
          debugPrint(
            '[AI-chan][VoiceCall] Timeout 10s ignorado: audio=$hasAudio userSpoke=$userSpoke endTag=$_endCallTagHandled',
          );
        }
      });
    }
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
