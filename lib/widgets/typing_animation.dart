import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class TypingAnimation extends StatefulWidget {
  const TypingAnimation({super.key});

  @override
  State<TypingAnimation> createState() => _TypingAnimationState();
}

class _TypingAnimationState extends State<TypingAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1;
  late Animation<double> _dot2;
  late Animation<double> _dot3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat();
    _dot1 = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );
    _dot2 = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeIn),
      ),
    );
    _dot3 = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(opacity: _dot1.value, child: _buildDot()),
              Opacity(opacity: _dot2.value, child: _buildDot()),
              Opacity(opacity: _dot3.value, child: _buildDot()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
    );
  }
}
