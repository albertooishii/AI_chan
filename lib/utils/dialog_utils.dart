import 'package:flutter/material.dart';
import 'package:ai_chan/utils/log_utils.dart';
import '../constants/app_colors.dart';

import 'package:ai_chan/main.dart';

Future<void> showSuccessDialog(BuildContext context, String title, String message) async {
  final ctx = (context.mounted) ? context : navigatorKey.currentContext;
  if (ctx == null) return;
  return showDialog<void>(
    context: ctx,
    builder: (ctx2) => AlertDialog(
      backgroundColor: Colors.black,
      title: Text(title, style: const TextStyle(color: Colors.cyanAccent)),
      content: Text(message, style: const TextStyle(color: Colors.cyanAccent)),
      actions: [
        TextButton(
          child: const Text('OK', style: TextStyle(color: Colors.pinkAccent)),
          onPressed: () => Navigator.of(ctx2).pop(),
        ),
      ],
    ),
  );
}

/// Muestra un diálogo de error centralizado
Future<void> showErrorDialog(BuildContext context, String error) async {
  Log.e('Error mostrado', tag: 'DIALOG_UTILS', error: error);
  // Si el error contiene 'unmounted', solo loguea pero permite mostrar el diálogo normalmente
  final ctx = (context.mounted) ? context : navigatorKey.currentContext;
  if (ctx == null) {
    // Fallback: mostrar SnackBar si no hay contexto válido
    Log.w('No hay contexto válido para mostrar el diálogo de error: $error', tag: 'DIALOG_UTILS');
    // Si hay un ScaffoldMessenger disponible, mostrar SnackBar
    final navState = navigatorKey.currentState;
    final navContext = navState?.context;
    final scaffoldMessenger = navContext != null ? ScaffoldMessenger.maybeOf(navContext) : null;
    if (scaffoldMessenger != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    return;
  }
  return showDialog(
    context: ctx,
    builder: (ctx2) => AlertDialog(
      backgroundColor: Colors.black,
      title: const Text('Error', style: TextStyle(color: AppColors.secondary)),
      content: Text(error, style: const TextStyle(color: AppColors.primary)),
      actions: [
        TextButton(
          child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
          onPressed: () => Navigator.of(ctx2).pop(),
        ),
      ],
    ),
  );
}
