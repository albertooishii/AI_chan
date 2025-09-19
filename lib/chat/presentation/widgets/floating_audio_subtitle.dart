import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_chan/shared.dart'; // Updated to shared location
import 'package:ai_chan/shared/presentation/controllers/audio_subtitle_controller.dart';

/// Widget de subtítulo flotante con efecto cyberpunk para reproducción de audio
class FloatingAudioSubtitle extends StatefulWidget {
  // permitir desactivar katakana si la fuente no soporta

  const FloatingAudioSubtitle({
    super.key,
    required this.controller,
    this.style = const TextStyle(
      color: Colors.cyanAccent,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.25,
    ),
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.maxWidth = 380,
    this.glassBackground = true,
    this.scramblePerChar = const Duration(milliseconds: 140),
    this.removalDuration = const Duration(milliseconds: 220),
    this.alignment = Alignment.bottomCenter,
    this.decorationOverride,
    this.useKatakana = false,
  });
  final AudioSubtitleController controller;
  final TextStyle style;
  final EdgeInsets padding;
  final double maxWidth;
  final bool glassBackground;
  final Duration scramblePerChar;
  final Duration removalDuration;
  final Alignment alignment;
  final BoxDecoration? decorationOverride;
  final bool useKatakana;

  @override
  State<FloatingAudioSubtitle> createState() => _FloatingAudioSubtitleState();
}

class _FloatingAudioSubtitleState extends State<FloatingAudioSubtitle> {
  late StreamSubscription<String> _sub;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.progressiveTextStream.listen((final txt) {
      if (!mounted) return;
      setState(() => _current = txt);
    });
  }

  @override
  void dispose() {
    try {
      _sub.cancel();
    } on Exception catch (_) {}
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    if (_current.isEmpty) return const SizedBox.shrink();
    final subtitle = CyberpunkRealtimeSubtitle(
      text: _current,
      style: widget.style,
      scramblePerChar: widget.scramblePerChar,
      removalDuration: widget.removalDuration,
      useKatakana: widget.useKatakana,
    );
    Widget child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: subtitle,
    );
    if (widget.glassBackground) {
      child = Container(
        padding: widget.padding,
        decoration:
            widget.decorationOverride ??
            BoxDecoration(
              // Reemplazo de withOpacity (deprecado) por withValues conservando alpha
              color: Colors.black.withValues(alpha: 0.35),
              border: Border.all(
                color: Colors.cyanAccent.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.20),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
        child: child,
      );
    }
    return Align(alignment: widget.alignment, child: child);
  }
}
