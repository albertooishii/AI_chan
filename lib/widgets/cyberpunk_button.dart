import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CyberpunkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon; // Nuevo parámetro opcional

  const CyberpunkButton({required this.text, required this.onPressed, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.secondary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'FiraMono', fontSize: 18, letterSpacing: 2),
        shadowColor: AppColors.secondary,
        elevation: 10,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 8)],
          Text(text),
        ],
      ),
    );
  }
}
