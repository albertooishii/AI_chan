import 'dart:io';
import 'dart:ui';
import 'package:ai_chan/shared/utils/download_image.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:flutter/services.dart';
import 'package:ai_chan/main.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';

class ExpandableImageDialog {
  /// images: lista de mensajes con imagePath válido
  /// initialIndex: índice de la imagen a mostrar primero
  static void show(List<Message> images, int initialIndex, {Directory? imageDir}) {
    // Show the dialog using the app's global navigator so callers don't need
    // to pass a BuildContext (avoids accidental use across async gaps).
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    final ctx = navState.overlay?.context ?? navState.context;
    showAppDialog(
      context: ctx,
      barrierDismissible: true,
      // Importante: abrir el diálogo en el navigator local (no en el root)
      // para que el ScaffoldMessenger raíz (scaffoldMessengerKey) pueda
      // mostrar SnackBars por encima del diálogo.
      useRootNavigator: false,
      builder: (context) => _GalleryImageViewerDialog(images: images, initialIndex: initialIndex, imageDir: imageDir),
    );
  }
}

class _GalleryImageViewerDialog extends StatefulWidget {
  final List<Message> images;
  final int initialIndex;
  final Directory? imageDir;
  const _GalleryImageViewerDialog({required this.images, required this.initialIndex, this.imageDir});

  @override
  State<_GalleryImageViewerDialog> createState() => _GalleryImageViewerDialogState();
}

class _GalleryImageViewerDialogState extends State<_GalleryImageViewerDialog> {
  bool _showText = true;

  void _showImageDescriptionDialog(String? description) {
    if (!mounted) return;
    // Compute a safe context from the global navigator/overlay so we don't rely
    // on the dialog's BuildContext across async gaps. If there's no global
    // navigator, abort showing the description dialog.
    final globalNav = navigatorKey.currentState;
    if (globalNav == null) return;
    final safeContext = globalNav.overlay?.context ?? globalNav.context;
    showAppDialog(
      context: safeContext,
      useRootNavigator: true, // ✅ Asegurar que aparece encima del dialog de imagen
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Descripción de la imagen', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(description ?? 'Sin descripción.', style: const TextStyle(color: Colors.white)),
        ),
        actions: [
          TextButton(
            child: const Text('Copiar', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final text = description ?? '';

              if (text.isEmpty) {
                // Try to pop using the global navigator
                navigatorKey.currentState?.maybePop();
                return;
              }

              await Clipboard.setData(ClipboardData(text: text));

              // Resolve a fresh navigator/overlay after the async gap and show a snack.
              final postNav = navigatorKey.currentState;
              final postOverlayCtx = postNav?.overlay?.context;
              if (postOverlayCtx != null) {
                showOverlaySnackBar('Descripción copiada al portapapeles');
              } else if (postNav != null) {
                showAppSnackBar('Descripción copiada al portapapeles');
              }

              // Close the dialogs via global navigator if possible
              navigatorKey.currentState?.maybePop();
            },
          ),
          TextButton(
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
            onPressed: () {
              final globalNav = navigatorKey.currentState;
              if (globalNav != null && globalNav.canPop()) {
                globalNav.pop();
              } else {
                navigatorKey.currentState?.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  late PageController _controller;
  late int _currentIndex;
  // Eliminada variable _showDownload (ya no se usa)
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
    // Asegura el foco al abrir el diálogo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onPageChanged(int idx) {
    setState(() => _currentIndex = idx);
  }

  DateTime? _lastKeyTime;
  void _onKey(KeyEvent event) {
    // Ignorar eventos duplicados en menos de 100ms
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      if (_lastKeyTime != null && now.difference(_lastKeyTime!).inMilliseconds < 100) {
        return;
      }
      _lastKeyTime = now;
      if (event.logicalKey == LogicalKeyboardKey.arrowRight && _currentIndex < widget.images.length - 1) {
        _controller.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _currentIndex > 0) {
        _controller.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    }
  }

  // Métodos _showIcon y _hideIcon eliminados (ya no se usan)

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: KeyboardListener(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: (event) => _onKey(event),
        child: Stack(
          children: [
            // Fondo con blur suave cuando se muestran los controles
            if (_showText)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                  child: Container(color: Colors.black.withValues(alpha: 0.2)),
                ),
              ),
            // Imagen y navegación (pantalla completa, esquinas redondeadas siempre)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: _showText ? Colors.transparent : Colors.black,
                  width: double.infinity,
                  height: double.infinity,
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: _onPageChanged,
                    itemCount: widget.images.length,
                    itemBuilder: (context, idx) {
                      final msg = widget.images[idx];
                      final relPath = msg.image?.url;
                      if (widget.imageDir == null || relPath == null || relPath.isEmpty) {
                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => Navigator.of(context).pop(),
                          child: Center(
                            child: Container(
                              color: Colors.grey[900],
                              width: 200,
                              height: 200,
                              child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
                            ),
                          ),
                        );
                      }
                      final absPath = '${widget.imageDir!.path}/${relPath.split('/').last}';
                      final file = File(absPath);
                      final exists = file.existsSync();
                      if (exists) {
                        return Stack(
                          children: [
                            // Área de cierre al hacer tap fuera de la imagen
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(),
                              ),
                            ),
                            // La imagen en sí
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() {
                                    _showText = !_showText;
                                  });
                                },
                                child: InteractiveViewer(
                                  minScale: 1.0,
                                  maxScale: 6.0,
                                  panEnabled: true,
                                  clipBehavior: Clip.none,
                                  child: Image.file(file, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => Navigator.of(context).pop(),
                        child: Center(
                          child: Container(
                            color: Colors.grey[900],
                            width: 200,
                            height: 200,
                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Controles y texto (encima de la imagen)
            if (_showText) ...[
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              // Botón de descarga y menú juntos en la esquina superior derecha
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 32),
                      tooltip: 'Descargar imagen',
                      onPressed: () async {
                        final relPath = widget.images[_currentIndex].image?.url;
                        if (relPath != null && relPath.isNotEmpty && widget.imageDir != null) {
                          // Construir ruta completa
                          final absPath = '${widget.imageDir!.path}/${relPath.split('/').last}';
                          final result = await downloadImage(absPath);

                          if (!mounted) return; // State no longer mounted

                          // Resolve a fresh overlay/context from the global navigator after the async gap.
                          final postNav = navigatorKey.currentState;
                          final postOverlayCtx = postNav?.overlay?.context;

                          if (!result.$1 && result.$2 != null) {
                            // Hay error específico
                            if (postOverlayCtx != null) {
                              showOverlaySnackBar('Error al descargar: ${result.$2}', isError: true);
                            }
                          } else if (result.$1) {
                            // Éxito
                            if (postOverlayCtx != null) {
                              showOverlaySnackBar('✅ Imagen guardada correctamente', isError: false);
                            }
                          }
                          // Si !result.$1 && result.$2 == null significa que el usuario canceló - no hacer nada
                        } else {
                          if (!mounted) return;
                          final globalCtx =
                              navigatorKey.currentState?.overlay?.context ?? navigatorKey.currentState?.context;
                          if (globalCtx != null) {
                            showOverlaySnackBar('Error: No se encontró la imagen', isError: true);
                          }
                        }
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 32),
                      tooltip: 'Opciones',
                      onSelected: (value) {
                        if (value == 'description') {
                          _showImageDescriptionDialog(widget.images[_currentIndex].image?.prompt);
                        }
                      },
                      itemBuilder: (context) {
                        return [const PopupMenuItem<String>(value: 'description', child: Text('Ver descripción'))];
                      },
                    ),
                  ],
                ),
              ),
            ],
            // Mostrar el texto solo si no es vacío y si _showText está activo
            if (_showText &&
                widget.images[_currentIndex].text.isNotEmpty &&
                widget.images[_currentIndex].text.trim() != '')
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(0, 0, 0, 0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.images[_currentIndex].text,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
