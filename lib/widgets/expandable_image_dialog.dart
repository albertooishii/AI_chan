import 'dart:io';
// import eliminado: '../utils/image_utils.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import '../models/message.dart';
import 'package:flutter/services.dart';
import '../utils/download_image.dart';

class ExpandableImageDialog {
  /// images: lista de mensajes con imagePath válido
  /// initialIndex: índice de la imagen a mostrar primero
  static void show(BuildContext context, List<Message> images, int initialIndex, {Directory? imageDir}) {
    showDialog(
      context: context,
      barrierDismissible: true,
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
    if (!context.mounted) return;
    showDialog(
      context: context,
      useRootNavigator: true,
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
                Navigator.of(ctx).pop();
                return;
              }
              // Capturar referencias antes del await para evitar usar context tras el gap
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);
              await Clipboard.setData(ClipboardData(text: text));
              // Usar referencias capturadas
              messenger.showSnackBar(const SnackBar(content: Text('Descripción copiada al portapapeles')));
              navigator.pop();
            },
          ),
          TextButton(
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(ctx).pop(),
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
      if (_lastKeyTime != null && now.difference(_lastKeyTime!).inMilliseconds < 100) return;
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
            // Fondo negro total si el texto está oculto, transparente si está visible
            Positioned.fill(child: Container(color: _showText ? Colors.transparent : Colors.black)),
            // Área de cierre al hacer tap fuera de la imagen
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).pop(),
                child: Container(),
              ),
            ),
            // Imagen y navegación (pantalla completa, esquinas redondeadas siempre)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: Colors.black,
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
                        return Center(
                          child: Container(
                            color: Colors.grey[900],
                            width: 200,
                            height: 200,
                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
                          ),
                        );
                      }
                      final absPath = '${widget.imageDir!.path}/${relPath.split('/').last}';
                      final file = File(absPath);
                      final exists = file.existsSync();
                      if (exists) {
                        return GestureDetector(
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
                        );
                      }
                      return Center(
                        child: Container(
                          color: Colors.grey[900],
                          width: 200,
                          height: 200,
                          child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
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
                        final file = widget.images[_currentIndex].image?.url;
                        if (file != null && file.isNotEmpty) {
                          final result = await downloadImage(file);
                          if (!result.$1 && result.$2 != null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('Error al descargar: ${result.$2}')));
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(const SnackBar(content: Text('Imagen guardada en Descargas')));
                            }
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
