import 'package:flutter/material.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import '../constants/app_colors.dart';

import 'package:ai_chan/main.dart';

// Tracks the currently visible overlay snack so we keep only one at a time.
OverlayEntry? _currentOverlaySnackBarEntry;

Future<void> showSuccessDialog(final String title, final String message) async {
  // Usar el navigatorKey global para obtener contexto, igual que showAppSnackBar
  final navState = navigatorKey.currentState;
  if (navState == null) return;

  return showAppDialog<void>(
    builder: (final ctx2) => AlertDialog(
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
Future<void> showErrorDialog(final String error) async {
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
    builder: (final ctx2) => AlertDialog(
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
  final String message, {
  final bool isError = false,
  final Duration duration = const Duration(seconds: 3),
  final SnackBarAction? action,

  /// Si true, usar el ScaffoldMessenger raíz si existe; por defecto false
  /// para usar la implementación basada en [Overlay] (más visible sobre dialogs).
  final bool preferRootMessenger = false,
}) {
  // Resolve a safe context via the global navigator key.
  final navState = navigatorKey.currentState;
  if (navState == null) return;
  final ctx = navState.overlay?.context ?? navState.context;

  if (preferRootMessenger) {
    // Remove overlay snack if any
    try {
      _currentOverlaySnackBarEntry?.remove();
    } on Exception catch (_) {}
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
  final String message, {
  final bool isError = false,
  final Duration duration = const Duration(seconds: 3),
  final SnackBarAction? action,
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
  } on Exception catch (_) {}
  _currentOverlaySnackBarEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (final ctx) {
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
                        } on Exception catch (_) {}
                        try {
                          entry.remove();
                        } on Object catch (_) {
                          // Capturar cualquier error al remover overlay
                        }
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
      if (_currentOverlaySnackBarEntry == entry) {
        entry.remove();
      }
    } on Object catch (_) {
      // Capturar cualquier error (AssertionError, Exception, etc.)
    }
    if (_currentOverlaySnackBarEntry == entry) {
      _currentOverlaySnackBarEntry = null;
    }
  });
}

/// Wrapper around Flutter's `showDialog` that uses the app's `navigatorKey`
/// as a fallback for `context` so dialogs can be triggered from anywhere.
/// Signature mirrors Flutter's `showDialog` to keep compatibility.
Future<T?> showAppDialog<T>({
  required final WidgetBuilder builder,
  final bool barrierDismissible = true,
  final Color? barrierColor,
  final String? barrierLabel,
  final bool useRootNavigator = true,
  final bool useSafeArea = true,
  final RouteSettings? routeSettings,
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
    builder: (final dialogCtx) {
      return Theme(
        data: baseTheme.copyWith(dialogTheme: tightened),
        child: Builder(
          builder: (final innerCtx) {
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

/// Widget para mostrar indicadores de carga estilo cyberpunk
///
/// Ejemplo de uso:
/// ```dart
/// if (isLoading && loadingMessage != null)
///   Padding(
///     padding: const EdgeInsets.only(bottom: 16.0),
///     child: CyberpunkLoader(
///       message: loadingMessage!,
///       showProgressBar: true, // opcional: muestra barra de progreso ASCII
///     ),
///   ),
/// ```
class CyberpunkLoader extends StatefulWidget {
  const CyberpunkLoader({
    super.key,
    required this.message,
    this.showProgressBar = false,
  });
  final String message;
  final bool showProgressBar;

  @override
  State<CyberpunkLoader> createState() => _CyberpunkLoaderState();
}

class _CyberpunkLoaderState extends State<CyberpunkLoader>
    with TickerProviderStateMixin {
  late AnimationController _dotsController;
  late AnimationController _progressController;
  late AnimationController _blinkController;

  int _dotCount = 0;
  int _progressStep = 0;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();

    // Animación de puntos suspensivos (cada 500ms)
    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _dotsController.addListener(() {
      if (_dotsController.isCompleted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4; // 0, 1, 2, 3, 0...
        });
        _dotsController.reset();
        _dotsController.forward();
      }
    });

    // Animación de barra de progreso (cada 300ms)
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _progressController.addListener(() {
      if (_progressController.isCompleted) {
        setState(() {
          _progressStep = (_progressStep + 1) % 20; // 20 pasos
        });
        _progressController.reset();
        _progressController.forward();
      }
    });

    // Animación de parpadeo (cada 800ms)
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _blinkController.addListener(() {
      if (_blinkController.isCompleted) {
        setState(() {
          _isVisible = !_isVisible;
        });
        _blinkController.reset();
        _blinkController.forward();
      }
    });

    // Iniciar todas las animaciones
    _dotsController.forward();
    if (widget.showProgressBar) {
      _progressController.forward();
    }
    _blinkController.forward();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _progressController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  String _buildDots() {
    return '.' * _dotCount + ' ' * (3 - _dotCount);
  }

  String _buildProgressBar() {
    if (!widget.showProgressBar) return '';

    final filled = '█' * _progressStep;
    final empty = '░' * (20 - _progressStep);
    return '\n[$filled$empty] ${_progressStep * 5}%';
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.7,
      duration: const Duration(milliseconds: 100),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: widget.message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontFamily: 'monospace',
              ),
            ),
            TextSpan(
              text: _buildDots(),
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 15,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.showProgressBar)
              TextSpan(
                text: _buildProgressBar(),
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
