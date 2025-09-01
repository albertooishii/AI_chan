import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:ai_chan/main.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/widgets/app_dialog.dart';

class ExpandableImageDialog {
  /// images: lista de mensajes con imagePath válido
  /// initialIndex: índice de la imagen a mostrar primero
  /// [onImageDeleted] callback receives the deleted AiImage (if any) so callers
  /// can update their authoritative state (for example, remove from saved avatars).
  static void show(
    List<Message> images,
    int initialIndex, {
    Directory? imageDir,
    void Function(AiImage?)? onImageDeleted,
  }) {
    // Show the dialog using the app's global navigator so callers don't need
    // to pass a BuildContext (avoids accidental use across async gaps).
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showAppDialog(
      // Importante: abrir el diálogo en el navigator local (no en el root)
      // para que el ScaffoldMessenger raíz (scaffoldMessengerKey) pueda
      // mostrar SnackBars por encima del diálogo.
      useRootNavigator: false,
      builder: (context) => _GalleryImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
        imageDir: imageDir,
        onImageDeleted: onImageDeleted,
      ),
    );
  }
}

class _GalleryImageViewerDialog extends StatefulWidget {
  final List<Message> images;
  final int initialIndex;
  final Directory? imageDir;
  final void Function(AiImage?)? onImageDeleted;
  const _GalleryImageViewerDialog({
    required this.images,
    required this.initialIndex,
    this.imageDir,
    this.onImageDeleted,
  });

  @override
  State<_GalleryImageViewerDialog> createState() =>
      _GalleryImageViewerDialogState();
}

class _GalleryImageViewerDialogState extends State<_GalleryImageViewerDialog> {
  bool _showText = true;

  void _showImageDescriptionDialog(String? description) async {
    // If the widget is no longer mounted (dialog dismissed), skip the description dialog
    if (!mounted) return;
    showAppDialog(
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Descripción de la imagen',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Text(
            description ?? 'Sin descripción.',
            style: const TextStyle(color: Colors.white),
          ),
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

              await Clipboard.setData(ClipboardData(text: text));

              // Usar showAppSnackBar como API unificada
              showAppSnackBar('Descripción copiada al portapapeles');

              // Close the dialog if context is still mounted
              if (ctx.mounted) Navigator.of(ctx).pop();
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
      if (_lastKeyTime != null &&
          now.difference(_lastKeyTime!).inMilliseconds < 100) {
        return;
      }
      _lastKeyTime = now;
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          _currentIndex < widget.images.length - 1) {
        _controller.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          _currentIndex > 0) {
        _controller.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Future<void> _confirmAndDeleteCurrentImage() async {
    if (!mounted) return;

    final msg = widget.images[_currentIndex];
    final relPath = msg.image?.url;

    final confirmed = await showAppDialog<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar imagen'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar esta imagen? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Intentar borrar el archivo si existe
    if (relPath != null && relPath.isNotEmpty && widget.imageDir != null) {
      try {
        final absPath = '${widget.imageDir!.path}/${relPath.split('/').last}';
        final file = File(absPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Mostrar aviso, pero continuar con la eliminación de la lista
        showAppSnackBar(
          'Advertencia: no se pudo borrar el archivo de imagen: $e',
          isError: true,
        );
      }
    }

    AiImage? deletedImg;
    // Eliminar del listado localmente y actualizar índice/página
    setState(() {
      final removed = widget.images.removeAt(_currentIndex);
      deletedImg = removed.image;
      if (_currentIndex >= widget.images.length) {
        _currentIndex = (widget.images.length - 1).clamp(
          0,
          widget.images.length - 1,
        );
      }
      // Reconstruir el PageController en la nueva posición para evitar inconsistencias
      _controller = PageController(initialPage: _currentIndex);
      // Si no quedan imágenes, cerrar el diálogo
      if (widget.images.isEmpty) {
        Navigator.of(navigatorKey.currentContext!).pop();
      }
    });

    // Notificar al llamador para que actualice su estado (p.ej., remover avatar guardado)
    try {
      widget.onImageDeleted?.call(deletedImg);
    } catch (_) {}

    showAppSnackBar('Imagen eliminada');
  }

  // Métodos _showIcon y _hideIcon eliminados (ya no se usan)

  @override
  Widget build(BuildContext context) {
    // Proteger contra cambios concurrentes en la lista de imágenes.
    // Si la lista queda vacía, cerrar el diálogo de forma segura.
    if (widget.images.isEmpty) {
      // Asegurar que el pop ocurra fuera del ciclo de construcción
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    // Mantener _currentIndex dentro de los límites válidos.
    if (_currentIndex < 0) _currentIndex = 0;
    if (_currentIndex >= widget.images.length) {
      _currentIndex = widget.images.length - 1;
    }

    final hasText =
        widget.images[_currentIndex].text.isNotEmpty &&
        widget.images[_currentIndex].text.trim() != '';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: KeyboardListener(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: (event) => _onKey(event),
        child: Stack(
          children: [
            // Fondo con blur suave cuando se muestran los controles.
            // Mantener el BackdropFilter siempre montado evita que el fondo
            // aparezca sin blur durante la transición. Animamos sólo la
            // capa de color encima para controlar visibilidad.
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                // El IgnorePointer y AnimatedOpacity gobiernan sólo la capa de color,
                // no el filtro en sí.
                child: IgnorePointer(
                  ignoring: !_showText,
                  child: AnimatedOpacity(
                    opacity: _showText ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                ),
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
                      if (widget.imageDir == null ||
                          relPath == null ||
                          relPath.isEmpty) {
                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => Navigator.of(context).pop(),
                          child: Center(
                            child: Container(
                              color: Colors.grey[900],
                              width: 200,
                              height: 200,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                                size: 80,
                              ),
                            ),
                          ),
                        );
                      }
                      final absPath =
                          '${widget.imageDir!.path}/${relPath.split('/').last}';
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
                                  // Only toggle overlay visibility. Avoid touching the PageController
                                  // to prevent temporary jumps back to the initial page.
                                  setState(() {
                                    _showText = !_showText;
                                  });
                                },
                                child: InteractiveViewer(
                                  minScale: 1.0,
                                  maxScale: 6.0,
                                  clipBehavior: Clip.none,
                                  child: Image.file(file, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                            // Etiqueta pequeña en la esquina inferior izquierda: "Avatar i/n · dd/MM/yyyy HH:mm"
                            // Mostrar siempre el contador; añadir la fecha si está disponible
                            if (_showText)
                              Builder(
                                builder: (ctx) {
                                  final msg = widget.images[_currentIndex];
                                  final img = msg.image;
                                  // Considerar avatar solo si tiene createdAtMs; muchas imágenes normales
                                  // pueden tener seed pero no createdAtMs.
                                  final bool isAvatar =
                                      img?.createdAtMs != null;
                                  final total = widget.images.length;
                                  final index = (_currentIndex + 1).clamp(
                                    1,
                                    total,
                                  );

                                  // decidir prefijo
                                  String label = isAvatar
                                      ? 'Avatar $index/$total'
                                      : 'Foto $index/$total';

                                  // fecha: para avatar preferir createdAtMs, para imágenes normales usar message.dateTime
                                  final int? ms = isAvatar
                                      ? img?.createdAtMs
                                      : msg.dateTime.millisecondsSinceEpoch;
                                  if (ms != null) {
                                    final dt =
                                        DateTime.fromMillisecondsSinceEpoch(ms);
                                    final formatted = DateFormat(
                                      'dd/MM/yyyy HH:mm',
                                    ).format(dt);
                                    label = '$label · $formatted';
                                  }

                                  return Positioned(
                                    left: 12,
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: (0.45 * 255)
                                              .round()
                                              .toDouble(),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 80,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Controles y texto (encima de la imagen) — siempre montados, se muestran con opacity
            Positioned(
              top: dialogTopOffset(context),
              left: dialogLeftOffset(context),
              child: IgnorePointer(
                ignoring: !_showText,
                child: AnimatedOpacity(
                  opacity: _showText ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: IconButton(
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.primary,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            // Botón de descarga y menú juntos en la esquina superior derecha
            Positioned(
              top: dialogTopOffset(context),
              right: dialogRightOffset(context),
              child: IgnorePointer(
                ignoring: !_showText,
                child: AnimatedOpacity(
                  opacity: _showText ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: const EdgeInsets.all(8),
                        icon: const Icon(
                          Icons.download,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        tooltip: 'Descargar imagen',
                        onPressed: () async {
                          final relPath =
                              widget.images[_currentIndex].image?.url;
                          if (relPath != null &&
                              relPath.isNotEmpty &&
                              widget.imageDir != null) {
                            // Construir ruta completa
                            final absPath =
                                '${widget.imageDir!.path}/${relPath.split('/').last}';
                            final result = await downloadImage(absPath);

                            if (!mounted) return; // State no longer mounted

                            if (!result.$1 && result.$2 != null) {
                              // Hay error específico
                              showAppSnackBar(
                                'Error al descargar: ${result.$2}',
                                isError: true,
                              );
                            } else if (result.$1) {
                              // Éxito
                              showAppSnackBar(
                                '✅ Imagen guardada correctamente',
                              );
                            }
                            // Si !result.$1 && result.$2 == null significa que el usuario canceló - no hacer nada
                          } else {
                            showAppSnackBar(
                              'Error: No se encontró la imagen',
                              isError: true,
                            );
                          }
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        tooltip: 'Opciones',
                        onSelected: (value) async {
                          if (value == 'description') {
                            _showImageDescriptionDialog(
                              widget.images[_currentIndex].image?.prompt,
                            );
                          } else if (value == 'delete') {
                            await _confirmAndDeleteCurrentImage();
                          }
                        },
                        itemBuilder: (context) {
                          return [
                            const PopupMenuItem<String>(
                              value: 'description',
                              child: Text(
                                'Ver descripción',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(
                                'Eliminar',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Mostrar texto (pie de foto) siempre montado, con animación de opacidad
            Positioned(
              bottom: 72,
              left: kAppDialogSidePadding,
              right: kAppDialogSidePadding,
              child: IgnorePointer(
                ignoring: !_showText || !hasText,
                child: AnimatedOpacity(
                  opacity: (_showText && hasText) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 18,
                    ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
