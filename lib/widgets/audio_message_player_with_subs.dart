import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:ai_chan/core/models.dart';
import '../providers/chat_provider.dart';
import 'audio_message_player.dart';
import 'floating_audio_subtitle.dart';

/// Widget compuesto: reproductor + subtítulo flotante cyberpunk sincronizado.
class AudioMessagePlayerWithSubs extends StatefulWidget {
  final Message message;
  final double width;
  final bool globalOverlay; // muestra subtítulos estilo video ocupando ancho pantalla
  const AudioMessagePlayerWithSubs({super.key, required this.message, this.width = 180, this.globalOverlay = true});

  @override
  State<AudioMessagePlayerWithSubs> createState() => _AudioMessagePlayerWithSubsState();
}

class _AudioMessagePlayerWithSubsState extends State<AudioMessagePlayerWithSubs> {
  late final AudioSubtitleController _subsCtrl;
  String _baseText = '';
  OverlayEntry? _overlayEntry;
  bool _wasPlaying = false;
  Timer? _throttleTimer; // ligera regulación de updates si fuese necesario
  Timer? _overlayRemovalTimer; // delay para desaparición
  Timer? _overlayFadeTimer; // timer que inicia el fade-out
  double _overlayOpacity = 1.0; // opacidad animada del overlay

  static const Duration _lingerTotal = Duration(seconds: 2); // tiempo visible tras terminar
  static const Duration _fadeOutDuration = Duration(milliseconds: 450); // duración del desvanecido final

  @override
  void initState() {
    super.initState();
    _subsCtrl = AudioSubtitleController();
    _prepareTimeline();
  }

  void _prepareTimeline() {
    final raw = widget.message.text;
    // Extraer contenido dentro de [audio] ... [/audio] si existe
    final lower = raw.toLowerCase();
    String content = raw;
    final openTag = '[audio]';
    final closeTag = '[/audio]';
    if (lower.contains(openTag) && lower.contains(closeTag)) {
      final start = lower.indexOf(openTag) + openTag.length;
      final end = lower.indexOf(closeTag, start);
      if (end > start) {
        content = raw.substring(start, end).trim();
      }
    }
    _baseText = content.trim();
    // Sanitizar: remover caracteres astrales (emojis u otros símbolos que muestran tofu) y control chars
    _baseText = _sanitizePlainText(_baseText);
  }

  String _sanitizePlainText(String input) {
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
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void didUpdateWidget(covariant AudioMessagePlayerWithSubs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.audioPath != widget.message.audioPath || oldWidget.message.text != widget.message.text) {
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
        builder: (ctx) {
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
                  glassBackground: true,
                  useKatakana: false,
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
        final chat = context.read<ChatProvider>();
        if (chat.isPlaying(widget.message)) return;
        _setOverlayOpacity(0.0);
      });
    } else {
      _setOverlayOpacity(0.0);
    }
    _overlayRemovalTimer = Timer(_lingerTotal, () {
      if (!mounted) return;
      // Si durante el delay volvió a reproducirse, no remover
      final chat = context.read<ChatProvider>();
      if (chat.isPlaying(widget.message)) return;
      _removeGlobalOverlay();
    });
  }

  void _setOverlayOpacity(double value) {
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
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final isPlaying = chat.isPlaying(widget.message);
    final pos = chat.playingPosition;
    final rawDur = chat.playingDuration;
    final hasRealDuration = rawDur.inMilliseconds > 0;
    final dur = hasRealDuration ? rawDur : const Duration(milliseconds: 1);

    // Gestionar overlay global estilo video
    if (widget.globalOverlay) {
      if (isPlaying && !_wasPlaying) {
        // Empezó: asegurar overlay visible y cancelar cualquier pending removal
        _showGlobalOverlay();
      } else if (!isPlaying && _wasPlaying) {
        // Acaba de terminar: garantizar que se vea el texto completo (puede que la
        // última actualización proporcional no haya llegado si el reproductor
        // emite STOP unos ms antes de la duración total) y mantener visible un par de segundos
        if (_baseText.isNotEmpty) {
          _subsCtrl.showFullTextInstant(_baseText);
        }
        _scheduleOverlayRemoval();
      }
    }

    _wasPlaying = isPlaying;

    if (isPlaying) {
      // Al momento justo de empezar (transición wasPlaying->isPlaying), limpiar para no mostrar completo
      if (!_wasPlaying) {
        _subsCtrl.clear();
        // Cancelar fade y restaurar opacidad completa por si venía de un linger anterior
        _overlayRemovalTimer?.cancel();
        _overlayFadeTimer?.cancel();
        _setOverlayOpacity(1.0);
      }
      // Solo actualizar cuando tengamos duración real y posición > 0 (evita flash de texto completo)
      if (hasRealDuration) {
        const revealDelay = Duration(milliseconds: 1000); // delay de arranque si no hay timestamps
        final bool hasTimeline = false; // por ahora siempre proporcional
        if (!hasTimeline && rawDur > revealDelay) {
          if (pos <= revealDelay) {
            // Aún dentro del delay inicial: mantener limpio
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              _subsCtrl.clear();
              _throttleTimer = Timer(const Duration(milliseconds: 45), () {});
            }
          } else {
            final effectivePos = pos - revealDelay;
            final adjustedTotal = rawDur - revealDelay;
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              _subsCtrl.updateProportional(
                effectivePos,
                _baseText,
                adjustedTotal > Duration.zero ? adjustedTotal : rawDur,
              );
              _throttleTimer = Timer(const Duration(milliseconds: 45), () {});
            }
          }
        } else {
          // Duración demasiado corta o hay timeline real: iniciar enseguida
          if (pos > Duration.zero) {
            if (_throttleTimer == null || !_throttleTimer!.isActive) {
              _subsCtrl.updateProportional(pos, _baseText, dur);
              _throttleTimer = Timer(const Duration(milliseconds: 45), () {});
            }
          }
        }
      }
    }

    if (widget.globalOverlay) {
      // Sólo mostrar reproductor sin subtítulo embebido
      return AudioMessagePlayer(message: widget.message, width: widget.width);
    }

    // Modo antiguo (subtítulo dentro del bubble)
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AudioMessagePlayer(message: widget.message, width: widget.width),
        if (isPlaying)
          Positioned(
            left: 0,
            right: 0,
            bottom: -54,
            child: FloatingAudioSubtitle(
              controller: _subsCtrl,
              alignment: Alignment.topCenter,
              glassBackground: true,
              maxWidth: widget.width + 120,
            ),
          ),
      ],
    );
  }
}
