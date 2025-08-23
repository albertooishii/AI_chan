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
  const AudioMessagePlayer({super.key, required this.message, this.width = 140, this.bars = 32});

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late List<int> _waveform; // sintética (0..100)
  int? _durationSeconds; // heurística calculada una vez

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _waveform = _generateWaveform(widget.bars, seed: widget.message.audioPath.hashCode);
    _computeDuration();
  }

  @override
  void didUpdateWidget(covariant AudioMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.audioPath != widget.message.audioPath) {
      _waveform = _generateWaveform(widget.bars, seed: widget.message.audioPath.hashCode);
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

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final isPlaying = chat.isPlaying(widget.message);
    final glowColor = widget.message.sender == MessageSender.user ? AppColors.primary : AppColors.secondary;
    final durationText = _durationSeconds != null ? _fmt(_durationSeconds!) : '--:--';
    // Use LayoutBuilder so the player expands to the bubble's available width.
    return LayoutBuilder(
      builder: (context, constraints) {
        double finalWidth;
        if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          finalWidth = constraints.maxWidth;
        } else {
          // Fallback to previous adaptive logic when not constrained by parent.
          final screenWidth = MediaQuery.of(context).size.width;
          if (screenWidth < 480) {
            finalWidth = screenWidth - 32; // móvil casi completo
          } else if (screenWidth < 900) {
            finalWidth = screenWidth * 0.7;
          } else {
            finalWidth = screenWidth * 0.5; // escritorio medio ancho
          }
          finalWidth = finalWidth.clamp(220, 720);
        }

        // Animar un leve cambio de alpha en las barras cuando está reproduciendo
        final t = _pulse.value; // 0..1
        return Semantics(
          label: 'Nota de voz, duración $durationText, ${isPlaying ? 'reproduciendo' : 'pausada'}',
          button: true,
          child: GestureDetector(
            onTap: () => chat.togglePlayAudio(widget.message),
            child: Container(
              width: finalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: glowColor, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: glowColor, size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const double barWidth = 6.0;
                          const double gap = 2.0;

                          // Cuántas barras caben manteniendo ancho fijo por barra+gap
                          final int maxFit = ((constraints.maxWidth + gap) / (barWidth + gap)).floor().clamp(1, 256);
                          final int showCount = maxFit;

                          // Muestrear `_waveform` para producir exactamente `showCount` valores
                          List<int> display;
                          if (_waveform.isEmpty) {
                            display = List<int>.filled(showCount, 0);
                          } else if (_waveform.length >= showCount) {
                            display = _waveform.sublist(_waveform.length - showCount);
                          } else {
                            display = List<int>.generate(showCount, (i) {
                              final idx = (i * _waveform.length / showCount).floor();
                              return _waveform[idx.clamp(0, _waveform.length - 1)];
                            });
                          }

                          if (display.length <= 1) {
                            final v = display.isEmpty ? 0 : display.first;
                            return Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: barWidth,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 240),
                                  height: 4 + (v / 100) * 22,
                                  decoration: BoxDecoration(
                                    color: isPlaying
                                        ? glowColor.withValues(
                                            alpha: ((0.55 + 0.35 * sin((t * 2 * pi) + v)).clamp(0, 1)).toDouble(),
                                          )
                                        : glowColor.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }

                          final toShow = display;
                          // Alinear a la derecha para que se vean las barras más recientes
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List<Widget>.generate(toShow.length * 2 - 1, (i) {
                              if (i.isEven) {
                                final val = toShow[i ~/ 2];
                                final a = isPlaying ? ((0.55 + 0.35 * sin((t * 2 * pi) + val)).clamp(0, 1)) : 0.45;
                                return SizedBox(
                                  width: barWidth,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 240),
                                    height: 4 + (val / 100) * 22,
                                    decoration: BoxDecoration(
                                      color: glowColor.withValues(alpha: a.toDouble()),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox(width: gap);
                            }),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(durationText, style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                  if (widget.message.autoTts && widget.message.sender != MessageSender.assistant) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.auto_mode, size: 14, color: Colors.orangeAccent),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
