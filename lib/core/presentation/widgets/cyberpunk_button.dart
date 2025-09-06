import 'package:flutter/material.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';

class CyberpunkButton extends StatelessWidget {
  // Nuevo parámetro opcional

  const CyberpunkButton({
    required this.text,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  Widget build(final BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.secondary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'FiraMono',
          fontSize: 18,
          letterSpacing: 2,
        ),
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
