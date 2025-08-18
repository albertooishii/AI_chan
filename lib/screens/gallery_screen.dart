import 'dart:io';
import '../utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import '../widgets/expandable_image_dialog.dart';

class GalleryScreen extends StatelessWidget {
  final List<Message> images;
  const GalleryScreen({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: getLocalImageDir(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final absDir = snapshot.data!;
        final existingImages = images.where((msg) {
          final relPath = msg.image?.url;
          if (relPath == null || relPath.isEmpty) return false;
          final absPath = '${absDir.path}/${relPath.split('/').last}';
          final file = File(absPath);
          return file.existsSync();
        }).toList();
        return Scaffold(
          appBar: AppBar(backgroundColor: Colors.black, elevation: 0, title: const Text('Galería de fotos')),
          body: existingImages.isEmpty
              ? const Center(child: Text('No hay imágenes en este chat'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: existingImages.length,
                  itemBuilder: (context, index) {
                    final msg = existingImages[index];
                    final relPath = msg.image?.url ?? '';
                    final absPath = '${absDir.path}/${relPath.split('/').last}';
                    final file = File(absPath);
                    return GestureDetector(
                      onTap: () {
                        ExpandableImageDialog.show(context, existingImages, index, imageDir: absDir);
                      },
                      child: Image.file(file, fit: BoxFit.cover),
                    );
                  },
                ),
        );
      },
    );
  }
}
