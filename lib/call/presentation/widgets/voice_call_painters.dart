import 'package:flutter/material.dart';

class CyberpunkGlowPainter extends CustomPainter {
  final Color baseColor;
  final Color accentColor;

  const CyberpunkGlowPainter({
    required this.baseColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accentColor.withAlpha((0.08 * 255).round()),
              baseColor.withAlpha((0.04 * 255).round()),
              Colors.transparent,
            ],
            stops: const [0.2, 0.6, 1.0],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width / 2, size.height / 2),
              radius: size.width * 0.7,
            ),
          );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.7,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WavePainter extends CustomPainter {
  final double animation;
  final double soundLevel;
  final Color baseColor;
  final Color accentColor;

  const WavePainter({
    required this.animation,
    required this.soundLevel,
    required this.baseColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const waveCount = 3;
    // soundLevel se espera en 0..1 (normalizado desde dBFS en la UI)
    // Aseguramos un mínimo visual de 0.1 y un máximo de 1.0
    final clamped = soundLevel.clamp(0.0, 1.0);
    final normalizedLevel = (0.1 + (clamped * 0.9));

    for (int i = 0; i < waveCount; i++) {
      final progress = ((animation + i / waveCount) % 1.0);
      final radius = maxRadius * progress * normalizedLevel;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final color = i.isEven ? baseColor : accentColor;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withAlpha(((0.25 * opacity) * 255).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is WavePainter) {
      return animation != oldDelegate.animation ||
          soundLevel != oldDelegate.soundLevel;
    }
    return false;
  }
}
