import 'package:record/record.dart';
import 'package:provider/provider.dart';

import '../services/openai_service.dart';
import '../services/voice_call_controller.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'voice_call_painters.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceCallChat extends StatefulWidget {
  const VoiceCallChat({super.key});

  @override
  State<VoiceCallChat> createState() => _VoiceCallChatState();
}

class _VoiceCallChatState extends State<VoiceCallChat> with SingleTickerProviderStateMixin {
  bool _hangupInProgress = false;
  bool _hangupNoticeShown = false; // evita mostrar SnackBar duplicado
  Future<void> _hangUp() async {
    if (_hangupInProgress) return;
    _hangupInProgress = true;
    // Mute inmediato para cortar el micrófono en UI
    controller.setMuted(true);
    // Capturar provider y transcript antes de navegar
    ChatProvider? chat;
    try {
      if (mounted) chat = context.read<ChatProvider>();
    } catch (_) {}
    final transcript = _aiCallTranscript.toString();
    // Parar animación y timers antes de cerrar la pantalla para evitar usar _controller tras dispose
    try {
      _subtitleTimer?.cancel();
      _levelSub?.cancel();
      _controller.stop();
    } catch (_) {}
    // Reproducir tono de colgado en background (no bloquear) y cerrar la pantalla inmediatamente
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
            // ignore: discarded_futures
            rootNav.maybePop();
          }
        } catch (_) {}
      }
    }
    // Limpieza en background: detener sesión de voz/mic y guardar resumen
    unawaited(() async {
      try {
        await controller.stop(keepFxPlaying: true).timeout(const Duration(milliseconds: 800));
      } catch (_) {
        // Ignorar timeout/errores
      }
      try {
        await _recorder.stop();
      } catch (_) {}
      try {
        await _recorder.dispose();
      } catch (_) {}
      try {
        if (transcript.trim().isNotEmpty) {
          await _saveCallSummaryIfAny(chat);
        }
      } catch (_) {}
    }());
  }

  // Subtítulos visibles por defecto; se ocultan si hay colgado por rechazo
  String _iaSubtitle = '';
  bool _hideSubtitles = false;
  Timer? _subtitleTimer;
  final OpenAIService openai = OpenAIService();
  late final VoiceCallController controller;
  final AudioRecorder _recorder = AudioRecorder();
  bool _muted = false;
  final StringBuffer _aiCallTranscript = StringBuffer();
  StreamSubscription<double>? _levelSub;

  void _showSubtitle(String text) {
    if (!mounted) return;
    if (!_hideSubtitles) {
      setState(() => _iaSubtitle = text);
    }
    // Acumular transcript de lo que dice la IA para memoria post-llamada
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isNotEmpty) {
      _aiCallTranscript.write(clean);
      _aiCallTranscript.write(' ');
      if (_aiCallTranscript.length > 8000) {
        final str = _aiCallTranscript.toString();
        _aiCallTranscript
          ..clear()
          ..write(str.substring(str.length - 8000));
      }
    }
    // Programar limpieza visual de subtítulo si está activo
    _subtitleTimer?.cancel();
    if (!_hideSubtitles) {
      _subtitleTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _iaSubtitle = '');
      });
    }
  }

  // (limpieza) _buildCallSystemPrompt y _profileDigest han sido eliminados al usar el SystemPrompt JSON unificado del ChatProvider.

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    controller = VoiceCallController(openAIService: openai);
    // Cargar voz activa guardada para marcarla en el menú
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final v = prefs.getString('selected_voice');
        if (v != null && mounted) setState(() => _activeVoice = v);
      } catch (_) {}
    });
    // Construir prompt con perfil e historial para ser la misma persona del chat.
    // Usar addPostFrameCallback para evitar leer Provider demasiado pronto.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String systemPrompt;
      try {
        final chat = context.read<ChatProvider>();
        // Usar SystemPrompt específico de llamada: mismas memorias, reglas adaptadas a voz
        systemPrompt = chat.buildCallSystemPromptJson(maxRecent: 32);
        debugPrint('VoiceCallChat: usando SystemPrompt JSON de llamada (len=${systemPrompt.length})');
      } catch (e) {
        debugPrint('VoiceCallChat: ChatProvider no disponible ($e). Simulando llamada no respondida.');
        if (!mounted) return;
        // Reproducir tono de no respuesta unos segundos y colgar
        await controller.playNoAnswerTone(duration: const Duration(seconds: 6));
        if (!mounted) return;
        await _hangUp();
        return; // no continuar a iniciar la sesión de voz
      }
      if (!mounted) return;
      await controller.startContinuousCall(
        systemPrompt: systemPrompt,
        onText: (chunk) => _showSubtitle(chunk),
        onHangupReason: (reason) async {
          // Ocultar subtítulos y mostrar aviso no invasivo explicando el motivo
          if (!mounted) return;
          setState(() => _hideSubtitles = true);
          // Mostrar un único SnackBar corto y claro; evitar duplicados si el callback se dispara más de una vez
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
          // Lanzar tono de colgado en background y colgar inmediatamente para volver al chat
          try {
            unawaited(controller.playHangupTone());
          } catch (_) {}
          await _hangUp();
        },
        recorder: _recorder,
        model: 'gpt-4o-mini-realtime',
      );
    });
    // Escuchar nivel normalizado 0..1 desde el controlador para animar el micrófono
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
    final activeVoice = _activeVoice; // reflejar voz elegida
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
            // Eliminado: indicador de carga de audio innecesario
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
            if (!_hideSubtitles && _iaSubtitle.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 110 + 72 + 8,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      _iaSubtitle,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

extension _CallSummary on _VoiceCallChatState {
  Future<void> _saveCallSummaryIfAny(ChatProvider? chat) async {
    try {
      final transcript = _aiCallTranscript.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      // No guardamos resumen si solo habló la IA (usuario no habló durante la sesión)
      final bool userSpoke = controller.userSpoke;
      if (transcript.isNotEmpty && chat != null && userSpoke) {
        final summary = _summarizeTranscript(transcript);
        debugPrint('[AI-chan][VoiceCall] Resumen de llamada (${summary.length} chars): $summary');
        await chat.addSystemMessage('Resumen de llamada (voz): $summary');
      }
      _aiCallTranscript.clear();
    } catch (_) {}
  }

  String _summarizeTranscript(String transcript) {
    // Heurística simple: tomar 4-5 frases distintas y compactarlas
    final parts = transcript.split(RegExp(r'[\.\!\?]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final seen = <String>{};
    final picked = <String>[];
    for (final p in parts) {
      final key = p.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      picked.add(p);
      if (picked.length >= 5) break;
    }
    if (picked.isEmpty) return transcript.length > 180 ? '${transcript.substring(0, 180)}…' : transcript;
    var text = '${picked.join('. ')}.';
    if (text.length > 420) text = '${text.substring(0, 420)}…';
    return text;
  }
}
