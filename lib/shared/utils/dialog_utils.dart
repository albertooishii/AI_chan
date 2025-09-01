import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import '../constants/app_colors.dart';

import 'package:ai_chan/main.dart';

// Tracks the currently visible overlay snack so we keep only one at a time.
OverlayEntry? _currentOverlaySnackBarEntry;

Future<void> showSuccessDialog(String title, String message) async {
  // Usar el navigatorKey global para obtener contexto, igual que showAppSnackBar
  final navState = navigatorKey.currentState;
  if (navState == null) return;

  return showAppDialog<void>(
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
Future<void> showErrorDialog(String error) async {
  Log.e('Error mostrado', tag: 'DIALOG_UTILS', error: error);

  // Usar el navigatorKey global para obtener contexto, igual que showAppSnackBar
  final navState = navigatorKey.currentState;
  if (navState == null) {
    // Fallback: mostrar SnackBar si no hay contexto válido
    Log.w(
      'No hay contexto válido para mostrar el diálogo de error: $error',
      tag: 'DIALOG_UTILS',
    );
    showAppSnackBar(error, isError: true);
    return;
  }

  return showAppDialog(
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
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,

  /// Si true, usar el ScaffoldMessenger raíz si existe; por defecto false
  /// para usar la implementación basada en [Overlay] (más visible sobre dialogs).
  bool preferRootMessenger = false,
}) {
  // Resolve a safe context via the global navigator key.
  final navState = navigatorKey.currentState;
  if (navState == null) return;
  final ctx = navState.overlay?.context ?? navState.context;

  if (preferRootMessenger) {
    // Remove overlay snack if any
    try {
      _currentOverlaySnackBarEntry?.remove();
    } catch (_) {}
    _currentOverlaySnackBarEntry = null;
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
  } else {
    _showOverlaySnackBar(
      message,
      isError: isError,
      duration: duration,
      action: action,
    );
  }
}

/// Muestra un mensaje tipo SnackBar directamente en el [Overlay] de la app.
/// Esto asegura que el mensaje se renderiza por encima de cualquier diálogo
/// modal que pudiera estar presente.
///
/// PRIVADO: Solo debe usarse internamente. La API pública es showAppSnackBar.
void _showOverlaySnackBar(
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  // Resolve a safe overlay context using the global navigator key so callers
  // don't need to pass a BuildContext (prevents use_build_context_synchronously).
  final navState = navigatorKey.currentState;
  if (navState == null) return;
  final overlay = navState.overlay;
  if (overlay == null) return;

  // Remove any existing overlay snack before inserting a new one (single instance)
  try {
    _currentOverlaySnackBarEntry?.remove();
  } catch (_) {}
  _currentOverlaySnackBarEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return Positioned(
        bottom: 24,
        left: 24,
        right: 24,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              decoration: BoxDecoration(
                color: isError
                    ? AppColors.secondary
                    : AppColors.cyberpunkYellow,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: isError ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      onPressed: () {
                        try {
                          action.onPressed();
                        } catch (_) {}
                        try {
                          entry.remove();
                        } catch (_) {}
                        if (_currentOverlaySnackBarEntry == entry) {
                          _currentOverlaySnackBarEntry = null;
                        }
                      },
                      child: Text(
                        action.label,
                        style: TextStyle(
                          color: isError ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  _currentOverlaySnackBarEntry = entry;
  overlay.insert(entry);
  Future.delayed(duration, () {
    try {
      entry.remove();
    } catch (_) {}
    if (_currentOverlaySnackBarEntry == entry) {
      _currentOverlaySnackBarEntry = null;
    }
  });
}

/// Wrapper around Flutter's `showDialog` that uses the app's `navigatorKey`
/// as a fallback for `context` so dialogs can be triggered from anywhere.
/// Signature mirrors Flutter's `showDialog` to keep compatibility.
Future<T?> showAppDialog<T>({
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
}) {
  // Resolve a safe context via the global navigator key so callers don't
  // need to pass a BuildContext. This avoids accidental capture of
  // widget contexts across async gaps.
  final navState = navigatorKey.currentState;
  if (navState == null) return Future.value();
  final ctx = navState.overlay?.context ?? navState.context;
  // Wrap the caller's builder result in a Theme that sets a responsive
  // dialog insetPadding so dialogs appear closer to the screen edges on
  // small devices. This centralizes margin behavior for all dialogs shown
  // through showAppDialog.
  final baseTheme = Theme.of(ctx);
  final screenWidth = MediaQuery.of(ctx).size.width;
  final horizontalMargin = screenWidth > 800 ? 40.0 : 4.0;
  final DialogThemeData tightened = baseTheme.dialogTheme.copyWith(
    insetPadding: EdgeInsets.symmetric(horizontal: horizontalMargin),
  );

  return showDialog<T>(
    context: ctx,
    builder: (dialogCtx) {
      return Theme(
        data: baseTheme.copyWith(dialogTheme: tightened),
        child: Builder(
          builder: (innerCtx) {
            // Invoke the original builder using an inner context so the
            // Theme we just inserted is visible to widgets that read
            // Theme.of(context) during their build (for example AlertDialog).
            return builder(innerCtx);
          },
        ),
      );
    },
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
  );
}
