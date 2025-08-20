import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// Guarda una imagen en la carpeta Descargas en Android. Devuelve (success, error) y deja el feedback al widget.
Future<(bool success, String? error)> downloadImage(String imagePath) async {
  try {
    final fileName = imagePath.split('/').last;
    final bytes = await File(imagePath).readAsBytes();
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar imagen',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [fileName.split('.').last],
      bytes: bytes,
    );
    if (result != null) {
      return (true, null);
    } else {
      return (false, null);
    }
  } catch (e) {
    return (false, 'Error al guardar imagen: $e');
  }
}
