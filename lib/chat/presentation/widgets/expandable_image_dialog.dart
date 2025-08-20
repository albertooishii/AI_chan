import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ai_chan/core/models.dart';

class ExpandableImageDialog {
  /// images: lista de mensajes con imagePath válido
  /// initialIndex: índice de la imagen a mostrar primero
  static void show(
    BuildContext context,
    List<Message> images,
    int initialIndex, {
    Directory? imageDir,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _GalleryImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
        imageDir: imageDir,
      ),
    );
  }
}

class _GalleryImageViewerDialog extends StatefulWidget {
  final List<Message> images;
  final int initialIndex;
  final Directory? imageDir;
  const _GalleryImageViewerDialog({
    required this.images,
    required this.initialIndex,
    this.imageDir,
  });

  @override
  State<_GalleryImageViewerDialog> createState() =>
      _GalleryImageViewerDialogState();
}

class _GalleryImageViewerDialogState extends State<_GalleryImageViewerDialog> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isZoomed = false;
  bool _uiVisible = true;
  final _transformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleUI() {
    if (mounted) setState(() => _uiVisible = !_uiVisible);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final canNavigate = widget.images.length > 1;
    final currentMsg = widget.images[_currentIndex];
    return PopScope(
      canPop: !_isZoomed,
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              // Visor de imágenes con PageView
              Center(
                child: canNavigate
                    ? PageView.builder(
                        controller: _pageController,
                        itemCount: widget.images.length,
                        onPageChanged: (index) =>
                            setState(() => _currentIndex = index),
                        itemBuilder: (context, index) => _ImageViewPage(
                          message: widget.images[index],
                          onZoomChanged: (zoomed) =>
                              setState(() => _isZoomed = zoomed),
                          onTap: _toggleUI,
                          transformKey: _transformKey,
                        ),
                      )
                    : _ImageViewPage(
                        message: currentMsg,
                        onZoomChanged: (zoomed) =>
                            setState(() => _isZoomed = zoomed),
                        onTap: _toggleUI,
                        transformKey: _transformKey,
                      ),
              ),

              // Barra superior (contador y botón cerrar)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                top: _uiVisible ? 0 : -80,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        canNavigate
                            ? Text(
                                '${_currentIndex + 1} / ${widget.images.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : const SizedBox.shrink(),
                        Row(
                          children: [
                            if (currentMsg.image?.url != null &&
                                File(currentMsg.image!.url!).existsSync()) ...[
                              IconButton(
                                onPressed: () async {
                                  // TODO: Implement download functionality if needed
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Función de descarga no implementada',
                                        ),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.download,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ],
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Indicador de página (solo si hay múltiples imágenes)
              if (canNavigate)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  bottom: _uiVisible ? 20 : -60,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.images.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentIndex
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
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

class _ImageViewPage extends StatefulWidget {
  final Message message;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;
  final GlobalKey transformKey;

  const _ImageViewPage({
    required this.message,
    required this.onZoomChanged,
    required this.onTap,
    required this.transformKey,
  });

  @override
  State<_ImageViewPage> createState() => _ImageViewPageState();
}

class _ImageViewPageState extends State<_ImageViewPage> {
  final _transformController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final nowZoomed = scale > 1.05; // pequeño umbral para evitar flickering
    if (nowZoomed != _isZoomed) {
      _isZoomed = nowZoomed;
      widget.onZoomChanged(nowZoomed);
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final imgPath = widget.message.image?.url;
    if (imgPath == null || !File(imgPath).existsSync()) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.grey, size: 64),
            SizedBox(height: 16),
            Text(
              'Imagen no encontrada',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return InteractiveViewer(
      key: widget.transformKey,
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 4.0,
      onInteractionEnd: (details) {
        // Si termina la interacción con un solo tap y no hay zoom, toggle UI
        if (!_isZoomed &&
            details.pointerCount == 0 &&
            details.velocity.pixelsPerSecond.distance < 300) {
          widget.onTap();
        }
      },
      child: GestureDetector(
        onDoubleTap: () {
          if (_isZoomed) {
            _resetZoom();
          } else {
            // Zoom 2x en el centro
            _transformController.value = Matrix4.identity()..scale(2.0, 2.0);
          }
          HapticFeedback.lightImpact();
        },
        child: Center(
          child: Hero(
            tag: 'image_${widget.message.image?.url}',
            child: Image.file(
              File(imgPath),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Error cargando imagen',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
