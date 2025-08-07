import 'dart:io';
import '../utils/image_utils.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import '../models/message.dart';
import 'package:flutter/services.dart';
import '../utils/download_image.dart';

class ExpandableImageDialog {
  /// images: lista de mensajes con imagePath válido
  /// initialIndex: índice de la imagen a mostrar primero
  static void show(BuildContext context, List<Message> images, int initialIndex) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _GalleryImageViewerDialog(images: images, initialIndex: initialIndex),
    );
  }
}

class _GalleryImageViewerDialog extends StatefulWidget {
  final List<Message> images;
  final int initialIndex;
  const _GalleryImageViewerDialog({required this.images, required this.initialIndex});

  @override
  State<_GalleryImageViewerDialog> createState() => _GalleryImageViewerDialogState();
}

class _GalleryImageViewerDialogState extends State<_GalleryImageViewerDialog> {
  void _showRevisedPromptDialog(String? revised) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Revised Prompt', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(revised ?? 'No hay revisedPrompt.', style: const TextStyle(color: Colors.white)),
        ),
        actions: [
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              // Capa para evitar que el tap en la imagen cierre el dialog
              Positioned.fill(child: Container(color: Colors.transparent)),
              Center(
                child: SizedBox.expand(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: _onPageChanged,
                    itemCount: widget.images.length,
                    itemBuilder: (context, idx) {
                      final msg = widget.images[idx];
                      final relPath = msg.image?.url;
                      return FutureBuilder<Directory>(
                        future: getLocalImageDir(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || relPath == null || relPath.isEmpty) {
                            return Center(
                              child: Container(
                                color: Colors.grey[900],
                                width: 200,
                                height: 200,
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
                              ),
                            );
                          }
                          final absPath = '${snapshot.data!.path}/${relPath.split('/').last}';
                          final file = File(absPath);
                          final exists = file.existsSync();
                          if (exists) {
                            return Center(
                              child: GestureDetector(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Stack(
                                    children: [
                                      InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
                                      // ...resto de la imagen y descarga...
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return Center(
                              child: Container(
                                color: Colors.grey[900],
                                width: 200,
                                height: 200,
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 80),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
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
                        if (value == 'revisedPrompt') {
                          _showRevisedPromptDialog(widget.images[_currentIndex].image?.prompt);
                        }
                      },
                      itemBuilder: (context) {
                        return [const PopupMenuItem<String>(value: 'revisedPrompt', child: Text('Ver revisedPrompt'))];
                      },
                    ),
                  ],
                ),
              ),
              // Mostrar el texto solo si no es vacío ni '[NO_REPLY]'
              if (widget.images[_currentIndex].text.isNotEmpty &&
                  widget.images[_currentIndex].text.trim() != '[NO_REPLY]')
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
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
      ),
    );
  }
}
