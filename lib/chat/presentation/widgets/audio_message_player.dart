import 'dart:io';
import 'dart:math';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_chan/core/models.dart';
import '../../application/providers/chat_provider.dart';

/// Reproductor compacto de mensajes de audio.
/// Extrae la lógica de ChatBubble para poder reutilizarlo / refactorizar.
class AudioMessagePlayer extends StatefulWidget {
  final Message message;
  final double width;
  final int bars; // número de barras de la forma de onda sintética
  const AudioMessagePlayer({
    super.key,
    required this.message,
    this.width = 140,
    this.bars = 32,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late List<int> _waveform; // sintética (0..100)
  int? _durationSeconds; // heurística calculada una vez

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _waveform = _generateWaveform(
      widget.bars,
      seed: widget.message.audioPath.hashCode,
    );
    _computeDuration();
  }

  @override
  void didUpdateWidget(covariant AudioMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.audioPath != widget.message.audioPath) {
      _waveform = _generateWaveform(
        widget.bars,
        seed: widget.message.audioPath.hashCode,
      );
      _durationSeconds = null;
      _computeDuration();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _computeDuration() {
    final path = widget.message.audioPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) {
        final bytes = f.lengthSync();
        // 96 kbps ≈ 12 KB/s
        _durationSeconds = (bytes / 12000).round().clamp(1, 60 * 60);
        setState(() {});
      }
    } catch (_) {}
  }

  List<int> _generateWaveform(int n, {int? seed}) {
    final rnd = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    return List.generate(n, (i) {
      final base = 40 + rnd.nextInt(55); // 40..94
      final mod = (sin(i / 2) * 20).abs();
      return (base + mod).clamp(0, 100).round();
    });
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final isPlaying = chat.isPlaying(widget.message);
    final glowColor = widget.message.sender == MessageSender.user
        ? AppColors.primary
        : AppColors.secondary;
    final durationText = _durationSeconds != null
        ? _fmt(_durationSeconds!)
        : '--:--';
    final screenWidth = MediaQuery.of(context).size.width;
    double adaptiveWidth;
    if (screenWidth < 480) {
      adaptiveWidth = screenWidth - 32; // móvil casi completo
    } else if (screenWidth < 900) {
      adaptiveWidth = screenWidth * 0.7;
    } else {
      adaptiveWidth = screenWidth * 0.5; // escritorio medio ancho
    }
    adaptiveWidth = adaptiveWidth.clamp(220, 720);

    // Animar un leve cambio de alpha en las barras cuando está reproduciendo
    final t = _pulse.value; // 0..1
    return Semantics(
      label:
          'Nota de voz, duración $durationText, ${isPlaying ? 'reproduciendo' : 'pausada'}',
      button: true,
      child: GestureDetector(
        onTap: () => chat.togglePlayAudio(widget.message),
        child: Container(
          width: adaptiveWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: glowColor, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: glowColor,
                size: 32,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final v in _waveform)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              height: 4 + (v / 100) * 22,
                              decoration: BoxDecoration(
                                color: (() {
                                  final a = isPlaying
                                      ? ((0.55 + 0.35 * sin((t * 2 * pi) + v))
                                            .clamp(0, 1))
                                      : 0.45;
                                  return glowColor.withValues(
                                    alpha: a.toDouble(),
                                  );
                                })(),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                durationText,
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              if (widget.message.autoTts) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.auto_mode,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
