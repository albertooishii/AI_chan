import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// Public constants and helpers to centralize dialog spacing and offsets so
// all dialogs and overlay controls can align to the same visual grid as
// the CalendarScreen AppBar.
const double kAppDialogSidePadding = 12.0;
const EdgeInsets kAppDialogInnerPadding = EdgeInsets.symmetric(vertical: 16.0, horizontal: kAppDialogSidePadding);

double dialogTopOffset(BuildContext context) => MediaQuery.of(context).padding.top + kAppDialogSidePadding;
double dialogLeftOffset(BuildContext context) => MediaQuery.of(context).padding.left + kAppDialogSidePadding;
double dialogRightOffset(BuildContext context) => MediaQuery.of(context).padding.right + kAppDialogSidePadding;

double dialogContentMaxWidth(BuildContext context) {
  final size = MediaQuery.of(context).size;
  return size.width - dialogLeftOffset(context) - dialogRightOffset(context);
}

/// AppAlertDialog: envoltorio ligero sobre AlertDialog con estilos de la app.
/// Acepta un título (Widget), contenido (Widget) y acciones. Opcionalmente se
/// pueden pasar ancho/alto para acomodar vistas grandes (por ejemplo vista previa JSON).
class AppAlertDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Widgets que se colocarán en la cabecera (AppBar.actions) del diálogo.
  final List<Widget>? headerActions;

  const AppAlertDialog({super.key, this.title, this.content, this.actions, this.headerActions});

  @override
  Widget build(BuildContext context) {
    // Force the dialog to cover the full screen, but keep an internal padding
    // so inner widgets (e.g., JSON preview) don't touch the device edges.
    final size = MediaQuery.of(context).size;
    final Widget finalContent = content ?? const SizedBox.shrink();

    // Padding lateral y vertical por defecto (12px laterales para coherencia con CalendarScreen)

    // Construir barra de título estilo AppBar (igual que CalendarScreen)
    // AppBar inside a SafeArea will provide correct top/side insets.
    final closeIcon = Navigator.of(context).canPop() ? Icons.arrow_back : Icons.close;

    // Si el título es un Text, aplicar estilo por defecto similar al AppBar
    Widget effectiveTitle;
    if (title is Text) {
      final t = title as Text;
      effectiveTitle = Text(
        t.data ?? '',
        style: t.style ?? const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: t.textAlign,
        overflow: t.overflow,
        maxLines: t.maxLines,
      );
    } else {
      effectiveTitle = title ?? const SizedBox.shrink();
    }

    // Use AppBar inside a SafeArea so it matches the CalendarScreen AppBar
    final Widget titleBar = SafeArea(
      top: true,
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: AppColors.primary,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: kAppDialogSidePadding),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                icon: Icon(closeIcon, color: AppColors.primary),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cerrar',
              ),
            ),
          ),
          title: effectiveTitle,
          actions: headerActions == null
              ? null
              : [
                  Padding(
                    padding: const EdgeInsets.only(right: kAppDialogSidePadding),
                    child: Row(mainAxisSize: MainAxisSize.min, children: headerActions!),
                  ),
                ],
        ),
      ),
    );

    // Compute content padding that aligns with the dialog-safe offsets used by
    // other modules (e.g. chat_json_utils) so labels and preview boxes line up.
    final leftPad = dialogLeftOffset(context);
    final rightPad = dialogRightOffset(context);
    final contentPadding = EdgeInsets.fromLTRB(
      leftPad,
      kAppDialogInnerPadding.top,
      rightPad,
      kAppDialogInnerPadding.bottom,
    );

    return AlertDialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      titlePadding: EdgeInsets.zero,
      title: titleBar,
      // We'll handle content padding manually by wrapping the content in
      // a full-screen SizedBox + Padding so inner widgets keep margins.
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: size.width,
        height: size.height,
        child: Padding(padding: contentPadding, child: finalContent),
      ),
      actions: actions,
    );
  }
}
