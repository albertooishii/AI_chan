import 'package:ai_chan/shared/utils/image_utils.dart' as image_utils;
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/application/services/file_ui_service.dart';
import 'dart:typed_data';
import '../widgets/expandable_image_dialog.dart';

class GalleryScreen extends StatefulWidget {
  final List<Message> images;
  final Future<void> Function(AiImage?)? onImageDeleted;
  const GalleryScreen({super.key, required this.images, this.onImageDeleted});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final FileUIService _fileUIService;

  @override
  void initState() {
    super.initState();
    _fileUIService = di.getFileUIService();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getImageDirPath(),
      builder: (context, dirSnapshot) {
        if (!dirSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final absDir = dirSnapshot.data!;
        return FutureBuilder<List<Message>>(
          future: _getExistingImages(absDir),
          builder: (context, imagesSnapshot) {
            if (!imagesSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final existingImages = imagesSnapshot.data!;
            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                title: const Text('Galería de fotos'),
              ),
              body: existingImages.isEmpty
                  ? const Center(child: Text('No hay imágenes en este chat'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: existingImages.length,
                      itemBuilder: (context, index) => _buildImageItem(
                        context,
                        existingImages,
                        index,
                        absDir,
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Future<String> _getImageDirPath() async {
    final dir = await image_utils.getLocalImageDir();
    return dir.path;
  }

  Future<List<Message>> _getExistingImages(String absDir) async {
    final existingImages = <Message>[];
    for (final msg in widget.images) {
      final relPath = msg.image?.url;
      if (relPath == null || relPath.isEmpty) continue;
      final absPath = '$absDir/${relPath.split('/').last}';
      if (await _fileUIService.fileExists(absPath)) {
        existingImages.add(msg);
      }
    }
    return existingImages;
  }

  Widget _buildImageItem(
    BuildContext context,
    List<Message> existingImages,
    int index,
    String absDir,
  ) {
    final msg = existingImages[index];
    final relPath = msg.image?.url ?? '';
    final absPath = '$absDir/${relPath.split('/').last}';

    return GestureDetector(
      onTap: () {
        ExpandableImageDialog.show(
          existingImages,
          index,
          imageBasePath: absDir,
          fileUIService: _fileUIService,
          onImageDeleted: widget.onImageDeleted,
        );
      },
      child: FutureBuilder<List<int>?>(
        future: _fileUIService.readFileAsBytes(absPath),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) {
            return Container(
              color: Colors.grey[800],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          }
          return Image.memory(
            Uint8List.fromList(snapshot.data!),
            fit: BoxFit.cover,
          );
        },
      ),
    );
  }
}
