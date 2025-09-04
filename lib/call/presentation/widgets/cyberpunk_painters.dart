import 'dart:math';
import 'package:flutter/material.dart';

class CyberpunkGlowPainter extends CustomPainter {
  final Color baseColor;
  final Color accentColor;

  CyberpunkGlowPainter({required this.baseColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Crear gradiente radial con efectos de glow
    final center = Offset(size.width / 2, size.height / 2);

    // Círculo de resplandor principal
    paint.shader = RadialGradient(
      radius: 1.0,
      colors: [
        baseColor.withAlpha((0.1 * 255).round()),
        baseColor.withAlpha((0.05 * 255).round()),
        accentColor.withAlpha((0.03 * 255).round()),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));

    canvas.drawCircle(center, size.width / 2, paint);

    // Efectos adicionales de líneas cyberpunk
    _drawCyberpunkLines(canvas, size);
  }

  void _drawCyberpunkLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Líneas hexagonales con glow
    final hexPath = _createHexagonPath(size);

    // Glow exterior
    paint
      ..color = baseColor.withAlpha((0.3 * 255).round())
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
    canvas.drawPath(hexPath, paint);

    // Línea principal
    paint
      ..color = baseColor.withAlpha((0.6 * 255).round())
      ..strokeWidth = 1.5
      ..maskFilter = null;
    canvas.drawPath(hexPath, paint);
  }

  Path _createHexagonPath(Size size) {
    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.3;

    for (int i = 0; i < 6; i++) {
      final angle = (i * 60.0) * pi / 180.0;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(CyberpunkGlowPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class WavePainter extends CustomPainter {
  final double animation;
  final double soundLevel;
  final Color baseColor;
  final Color accentColor;

  WavePainter({
    required this.animation,
    required this.soundLevel,
    required this.baseColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.stroke;

    // Ajustar intensidad basada en el nivel de sonido
    final intensity = (soundLevel * 2.0).clamp(0.0, 1.0);
    final waveCount = 3 + (intensity * 2).round();

    for (int i = 0; i < waveCount; i++) {
      final progress = (animation + i * 0.2) % 1.0;
      final radius = progress * (size.width / 2) * (0.8 + intensity * 0.4);
      final opacity = (1.0 - progress) * (0.6 + intensity * 0.4);

      // Glow exterior
      paint
        ..color = (i.isEven ? baseColor : accentColor).withAlpha(
          ((opacity * 0.3) * 255).round(),
        )
        ..strokeWidth = 6.0 + intensity * 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawCircle(center, radius, paint);

      // Círculo principal
      paint
        ..color = (i.isEven ? baseColor : accentColor).withAlpha(
          (opacity * 255).round(),
        )
        ..strokeWidth = 2.0 + intensity * 2.0
        ..maskFilter = null;
      canvas.drawCircle(center, radius, paint);
    }

    // Partículas flotantes basadas en el nivel de sonido
    if (intensity > 0.3) {
      _drawSoundParticles(canvas, size, intensity);
    }
  }

  void _drawSoundParticles(Canvas canvas, Size size, double intensity) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final particleCount = (intensity * 12).round();

    for (int i = 0; i < particleCount; i++) {
      final angle =
          (i * 360.0 / particleCount + animation * 360.0) * pi / 180.0;
      final distance = (60.0 + sin(animation * pi * 2 + i) * 20.0) * intensity;
      final particleSize = 2.0 + intensity * 3.0;

      final x = center.dx + cos(angle) * distance;
      final y = center.dy + sin(angle) * distance;

      paint.color = (i.isEven ? baseColor : accentColor).withAlpha(
        ((intensity * 0.8) * 255).round(),
      );

      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.soundLevel != soundLevel ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.accentColor != accentColor;
  }
}
