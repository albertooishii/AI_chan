import 'package:flutter/material.dart';

/// Simple blinking dot used to indicate recording state.
class BlinkingDot extends StatefulWidget {
  const BlinkingDot({
    super.key,
    this.size = 12.0,
    this.color = Colors.redAccent,
    this.duration = const Duration(milliseconds: 900),
  });
  final double size;
  final Color color;
  final Duration duration;

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Three dots animated indicator (typing/recording). Color and size customizable.
class ThreeDotsIndicator extends StatefulWidget {
  const ThreeDotsIndicator({
    super.key,
    required this.color,
    this.dotSize = 6.0,
    this.duration = const Duration(milliseconds: 900),
  });
  final Color color;
  final double dotSize;
  final Duration duration;

  @override
  State<ThreeDotsIndicator> createState() => _ThreeDotsIndicatorState();
}

class _ThreeDotsIndicatorState extends State<ThreeDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (final context, _) {
        final phase = _ctrl.value;
        final int active = (phase * 3).floor().clamp(0, 2);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (final i) {
            final on = i == active;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                decoration: BoxDecoration(
                  color: widget.color.withAlpha(
                    on ? 255 : (0.25 * 255).round(),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
