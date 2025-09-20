import 'package:flutter/material.dart';
import 'dart:async';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/chat.dart';
import 'audio_message_player.dart';
import 'floating_audio_subtitle.dart';

/// Widget compuesto: reproductor + subtítulo flotante cyberpunk sincronizado.
class AudioMessagePlayerWithSubs extends StatefulWidget {
  const AudioMessagePlayerWithSubs({
    super.key,
    required this.message,
    this.width = 180,
    this.globalOverlay = true,
    this.isPlaying = _defaultIsPlaying,
    this.togglePlay = _defaultTogglePlay,
    this.getPlayingPosition,
    this.getPlayingDuration,
    required this.fileService,
  });
  final Message message;
  final double width;
  final bool
  globalOverlay; // muestra subtítulos estilo video ocupando ancho pantalla
  // Playback callbacks/readers injected by parent to avoid Provider here.
  final bool Function(Message) isPlaying;
  final Future<void> Function(Message) togglePlay;
  final Duration Function()? getPlayingPosition;
  final Duration Function()? getPlayingDuration;
  final FileUIService fileService;

  static bool _defaultIsPlaying(Message _) => false;
  static Future<void> _defaultTogglePlay(Message _) async {}

  @override
  State<AudioMessagePlayerWithSubs> createState() =>
      _AudioMessagePlayerWithSubsState();
}

class _AudioMessagePlayerWithSubsState
    extends State<AudioMessagePlayerWithSubs> {
  late final AudioSubtitleController _subsCtrl;
  String _baseText = '';
  OverlayEntry? _overlayEntry;
  bool _wasPlaying = false;
  Timer? _throttleTimer; // ligera regulación de updates si fuese necesario
  Timer? _overlayRemovalTimer; // delay para desaparición
  Timer? _overlayFadeTimer; // timer que inicia el fade-out
  double _overlayOpacity = 1.0; // opacidad animada del overlay

  static const Duration _lingerTotal = Duration(
    seconds: 2,
  ); // tiempo visible tras terminar
  static const Duration _fadeOutDuration = Duration(
    milliseconds: 450,
  ); // duración del desvanecido final

  @override
  void initState() {
    super.initState();
    _subsCtrl = AudioSubtitleController();
    _prepareTimeline();
  }

  void _prepareTimeline() {
    final raw = widget.message.text;
    // Usar el texto completo del mensaje como subtítulo; el use-case ya normaliza
    // la intención de TTS y el provider controla isAudio/audioPath.
    _baseText = raw.trim();
    // Sanitizar: remover caracteres astrales (emojis u otros símbolos que muestran tofu) y control chars
    _baseText = _sanitizePlainText(_baseText);
  }

  String _sanitizePlainText(final String input) {
    // Eliminar caracteres fuera del BMP (code points > 0xFFFF) y de control excepto saltos de línea/espacio
    final buf = StringBuffer();
    for (final rune in input.runes) {
      if (rune > 0xFFFF) continue; // descartar emojis / astrales
      if (rune == 0x0A || rune == 0x0D || rune == 0x09 || rune == 0x20) {
        // newline, CR, tab, space
        buf.writeCharCode(rune);
        continue;
      }
      if (rune < 0x20) continue; // controles
      // Opcional: filtrar símbolos de reemplazo
      if (rune == 0xFFFD) continue; // replacement char
      buf.writeCharCode(rune);
    }
    // Colapsar espacios múltiples
    return MessageTextProcessorService.collapseWhitespace(buf.toString());
  }

  @override
  void didUpdateWidget(covariant final AudioMessagePlayerWithSubs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.audio?.url != widget.message.audio?.url ||
        oldWidget.message.text != widget.message.text) {
      _prepareTimeline();
    }
  }

  void _showGlobalOverlay() {
    if (!mounted) return;
    if (!widget.globalOverlay) return;
    if (_overlayEntry != null) return;
    // Cancelar cualquier timer de eliminación pendiente: seguimos activos
    _overlayRemovalTimer?.cancel();
    _overlayFadeTimer?.cancel();
    _setOverlayOpacity(1.0);
    // Diferir inserción al final del frame actual para evitar modificar overlay durante build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_overlayEntry != null) return; // pudo haberse creado ya
      final overlay = Overlay.of(context);
      _overlayEntry = OverlayEntry(
        builder: (final ctx) {
          final media = MediaQuery.of(ctx);
          final screenWidth = media.size.width;
          final horizontalMargin = 16.0;
          final maxWidth = screenWidth - horizontalMargin * 2;
          final bottomLogicalOffset = 110.0; // altura sobre barra input/chat
          return Positioned(
            left: horizontalMargin,
            right: horizontalMargin,
            bottom: bottomLogicalOffset,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _overlayOpacity,
                duration: _fadeOutDuration,
                curve: Curves.easeOut,
                child: FloatingAudioSubtitle(
                  controller: _subsCtrl,
                  alignment: Alignment.center,
                  maxWidth: maxWidth,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                    letterSpacing: 0.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_overlayEntry!);
    });
  }

  void _removeGlobalOverlay() {
    if (_overlayEntry == null) return;
    // Eliminación inmediata (privado) usada tras el delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _scheduleOverlayRemoval() {
    if (_overlayEntry == null) return; // nada que eliminar
    _overlayRemovalTimer?.cancel();
    _overlayFadeTimer?.cancel();
    // Programar inicio de fade antes del removal final
    final fadeStart = _lingerTotal - _fadeOutDuration;
    if (fadeStart > Duration.zero) {
      _overlayFadeTimer = Timer(fadeStart, () {
        if (!mounted) return;
        // Si volvió a reproducirse, cancelar fade
        if (widget.isPlaying(widget.message)) return;
        _setOverlayOpacity(0.0);
      });
    } else {
      _setOverlayOpacity(0.0);
    }
    _overlayRemovalTimer = Timer(_lingerTotal, () {
      if (!mounted) return;
      // Si durante el delay volvió a reproducirse, no remover
      if (widget.isPlaying(widget.message)) return;
      _removeGlobalOverlay();
    });
  }

  void _setOverlayOpacity(final double value) {
    if (_overlayOpacity == value) return;
    _overlayOpacity = value;
    if (mounted) {
      setState(() {});
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _overlayRemovalTimer?.cancel();
    _overlayFadeTimer?.cancel();
    _removeGlobalOverlay();
    _subsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final isPlaying = widget.isPlaying(widget.message);
    final pos = widget.getPlayingPosition?.call() ?? Duration.zero;
    final rawDur = widget.getPlayingDuration?.call() ?? Duration.zero;
    final hasRealDuration = rawDur.inMilliseconds > 0;

    // Prioridad de duración: real del AudioPlayer > almacenada en mensaje > estimada
    Duration dur;
    if (hasRealDuration) {
      dur = rawDur;
    } else if (widget.message.audio?.duration != null) {
      dur = widget.message.audio!.duration!;
      debugPrint(
        '[Subs] Using stored message duration: ${dur.inMilliseconds}ms',
      );
    } else if (isPlaying && pos.inMilliseconds > 0) {
      // Estimar duración basada en el progreso actual (asumiendo ~10s promedio)
      dur = const Duration(seconds: 10);
      debugPrint('[Subs] Using estimated duration for progressive reveal');
    } else {
      dur = const Duration(milliseconds: 1);
    }

    // Debug temporal - mostrar valores actuales
    if (isPlaying) {
      debugPrint(
        '[Subs] isPlaying=$isPlaying, pos=${pos.inMilliseconds}ms, rawDur=${rawDur.inMilliseconds}ms, msgDur=${widget.message.audio?.duration?.inMilliseconds}ms, finalDur=${dur.inMilliseconds}ms, hasReal=$hasRealDuration, textLen=${_baseText.length}',
      );
    }

    // Gestionar overlay/global o subtítulo embebido estilo video
    final prevWasPlaying = _wasPlaying;
    if (isPlaying && !prevWasPlaying) {
      // Empezó: limpiar subtítulos previos y mostrar overlay global si aplica
      _subsCtrl.clear();
      _overlayRemovalTimer?.cancel();
      _overlayFadeTimer?.cancel();
      _setOverlayOpacity(1.0);
      if (widget.globalOverlay) {
        _showGlobalOverlay();
      }
    } else if (!isPlaying && prevWasPlaying) {
      // Acaba de terminar: mantener estado actual de subtítulos
      debugPrint(
        '[Subs] Playback stopped - maintaining current subtitle state',
      );
      if (widget.globalOverlay) {
        // comportamiento previo: fade + removal del overlay global
        _scheduleOverlayRemoval();
      } else {
        // Para subtítulos embebidos (sin overlay global) programar limpieza automática
        _overlayRemovalTimer?.cancel();
        _overlayFadeTimer?.cancel();
        _overlayRemovalTimer = Timer(_lingerTotal, () {
          if (!mounted) return;
          // si volvió a reproducir, cancelar la limpieza (usando el reader inyectado)
          if (widget.isPlaying(widget.message)) return;
          _subsCtrl.clear();
        });
      }
    }

    _wasPlaying = isPlaying;

    // Actualizar subtítulos durante la reproducción
    if (isPlaying) {
      // Intentar progressive reveal si tenemos posición válida y texto
      if (pos >= Duration.zero && _baseText.isNotEmpty) {
        debugPrint(
          '[Subs] Progressive reveal conditions met - starting subtitle update logic',
        );
        // Pequeño delay inicial para evitar flash de texto completo
        const revealDelay = Duration(milliseconds: 500);

        if (dur > revealDelay) {
          if (pos <= revealDelay) {
            // Durante el delay inicial: mantener subtítulos limpios
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              debugPrint('[Subs] In delay period: clearing subtitles');
              _subsCtrl.clear();
              _throttleTimer = Timer(const Duration(milliseconds: 100), () {});
            }
          } else {
            // Después del delay: mostrar progresivamente
            final effectivePos = pos - revealDelay;
            final adjustedDur = dur - revealDelay;
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              debugPrint(
                '[Subs] Progressive reveal: effectivePos=${effectivePos.inMilliseconds}ms, adjustedDur=${adjustedDur.inMilliseconds}ms',
              );
              _subsCtrl.updateProportional(
                effectivePos,
                _baseText,
                adjustedDur,
              );
              _throttleTimer = Timer(const Duration(milliseconds: 100), () {});
            }
          }
        } else {
          // Audio muy corto: mostrar inmediatamente sin delay
          if (pos > Duration.zero) {
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              debugPrint('[Subs] Short audio: immediate reveal');
              _subsCtrl.updateProportional(pos, _baseText, dur);
              _throttleTimer = Timer(const Duration(milliseconds: 100), () {});
            }
          }
        }
      } else {
        debugPrint(
          '[Subs] Cannot do progressive reveal: pos=${pos.inMilliseconds}ms, textEmpty=${_baseText.isEmpty}',
        );
      }
    } else {
      debugPrint('[Subs] Not playing - no subtitle updates');
    }

    if (widget.globalOverlay) {
      return AudioMessagePlayer(
        message: widget.message,
        width: widget.width,
        isPlaying: isPlaying,
        onTap: () async => await widget.togglePlay(widget.message),
        fileService: widget.fileService,
      );
    }

    return AudioMessagePlayer(
      message: widget.message,
      width: widget.width,
      isPlaying: isPlaying,
      onTap: () async => await widget.togglePlay(widget.message),
      fileService: widget.fileService,
    );
  }
}
