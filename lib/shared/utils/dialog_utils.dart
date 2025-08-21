import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import '../constants/app_colors.dart';

import 'package:ai_chan/main.dart';

Future<void> showSuccessDialog(
  BuildContext context,
  String title,
  String message,
) async {
  // Reuse unified showdialog wrapper to keep behavior consistent across app.
  final ctx = (context.mounted) ? context : navigatorKey.currentContext;
  if (ctx == null) return;
  return showAppDialog<void>(
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
    Log.w(
      'No hay contexto válido para mostrar el diálogo de error: $error',
      tag: 'DIALOG_UTILS',
    );
    // Si hay un ScaffoldMessenger disponible, mostrar SnackBar
    final navState = navigatorKey.currentState;
    final navContext = navState?.context;
    final scaffoldMessenger = navContext != null
        ? ScaffoldMessenger.maybeOf(navContext)
        : null;
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

  return showAppDialog(
    context: ctx,
    builder: (ctx2) => AlertDialog(
      backgroundColor: Colors.black,
      title: const Text('Error', style: TextStyle(color: AppColors.secondary)),
      content: Text(error, style: const TextStyle(color: AppColors.primary)),
      actions: [
        TextButton(
          child: const Text(
            'Cerrar',
            style: TextStyle(color: AppColors.primary),
          ),
          onPressed: () => Navigator.of(ctx2).pop(),
        ),
      ],
    ),
  );
}

/// Muestra un SnackBar usando los componentes nativos de Flutter.
/// - Si `isError` es false: fondo amarillo (`AppColors.cyberpunkYellow`) y texto negro.
/// - Si `isError` es true: fondo `AppColors.secondary` (pinkAccent) y texto blanco.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final ctx = (context.mounted) ? context : navigatorKey.currentContext;
  if (ctx == null) return;

  final messenger = ScaffoldMessenger.of(ctx);

  final resolvedBackground = isError
      ? AppColors.secondary
      : AppColors.cyberpunkYellow;
  final resolvedText = isError ? Colors.white : Colors.black;

  final snack = SnackBar(
    content: Text(message, style: TextStyle(color: resolvedText)),
    backgroundColor: resolvedBackground,
    duration: duration,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    action: action,
  );

  messenger.showSnackBar(snack);
}

/// Wrapper around Flutter's `showDialog` that uses the app's `navigatorKey`
/// as a fallback for `context` so dialogs can be triggered from anywhere.
/// Signature mirrors Flutter's `showDialog` to keep compatibility.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
}) {
  final ctx = (context.mounted) ? context : navigatorKey.currentContext;
  if (ctx == null) return Future.value(null);
  return showDialog<T>(
    context: ctx,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
  );
}
