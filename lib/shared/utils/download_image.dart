import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Guarda una imagen en la carpeta Descargas en Android. Devuelve (success, error) y deja el feedback al widget.
Future<(bool success, String? error)> downloadImage(String imagePath) async {
  try {
    final fileName = imagePath.split('/').last;
    final bytes = await File(imagePath).readAsBytes();

    // Log de depuración
    debugPrint(
      '[downloadImage] Preparando para guardar: $fileName, bytes=${bytes.length}',
    );

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar imagen',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [fileName.split('.').last],
      bytes: bytes,
    );

    debugPrint('[downloadImage] FilePicker result: $result');

    if (result != null) {
      final savedFile = File(result);
      // Si ya existe, éxito
      if (await savedFile.exists()) {
        debugPrint('[downloadImage] Archivo existe en: $result');
        return (true, null);
      }

      // Intentar escribir los bytes manualmente (fallback si FilePicker no creó el archivo)
      try {
        await savedFile.writeAsBytes(bytes);
        if (await savedFile.exists()) {
          debugPrint('[downloadImage] Archivo creado manualmente en: $result');
          return (true, null);
        } else {
          debugPrint('[downloadImage] Falló creación manual en: $result');
          return (
            false,
            'No se pudo crear el archivo en la ubicación especificada',
          );
        }
      } catch (e, st) {
        debugPrint('[downloadImage] Error al escribir manualmente: $e\n$st');
        return (false, 'Error al guardar imagen: $e');
      }
    } else {
      // El usuario canceló el diálogo de guardado - no es un error
      return (false, null); // null error significa cancelación, no error
    }
  } catch (e, st) {
    debugPrint('[downloadImage] Exception: $e\n$st');
    return (false, 'Error al guardar imagen: $e');
  }
}
