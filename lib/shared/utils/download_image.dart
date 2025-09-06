import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Guarda una imagen en la carpeta Descargas en Android. Devuelve (success, error) y deja el feedback al widget.
Future<(bool success, String? error)> downloadImage(
  final String imagePath,
) async {
  try {
    final fileName = imagePath.split('/').last;
    final bytes = await File(imagePath).readAsBytes();

    // Log de depuración
    Log.d(
      '[downloadImage] Preparando para guardar: $fileName, bytes=${bytes.length}',
    );

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar imagen',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [fileName.split('.').last],
      bytes: bytes,
    );

    Log.d('[downloadImage] FilePicker result: $result');

    if (result != null) {
      Log.d('[downloadImage] FilePicker result: $result');

      // En Android FilePicker puede devolver rutas SAF/content (p.ej. '/document/primary:...')
      // No debemos usar dart:io File en esos casos.
      if (Platform.isAndroid) {
        final lower = result.toLowerCase();
        if (lower.startsWith('/document') ||
            lower.startsWith('content://') ||
            lower.contains('primary:')) {
          // Confiar en que FilePicker escribió los bytes correctamente
          Log.d(
            '[downloadImage] Ruta SAF/content detectada; confiar en FilePicker para guardar los bytes',
          );
          return (true, null);
        }
      }

      final savedFile = File(result);
      // Si ya existe, éxito
      if (savedFile.existsSync()) {
        Log.d('[downloadImage] Archivo existe en: $result');
        return (true, null);
      }

      // Intentar escribir los bytes manualmente (fallback si FilePicker no creó el archivo)
      try {
        await savedFile.writeAsBytes(bytes);
        if (savedFile.existsSync()) {
          Log.d('[downloadImage] Archivo creado manualmente en: $result');
          return (true, null);
        } else {
          Log.w('[downloadImage] Falló creación manual en: $result');
          return (
            false,
            'No se pudo crear el archivo en la ubicación especificada',
          );
        }
      } on Exception catch (e, st) {
        Log.e('[downloadImage] Error al escribir manualmente: $e\n$st');
        return (false, 'Error al guardar imagen: $e');
      }
    } else {
      // El usuario canceló el diálogo de guardado - no es un error
      return (false, null); // null error significa cancelación, no error
    }
  } on Exception catch (e, st) {
    Log.e('[downloadImage] Exception: $e\n$st');
    return (false, 'Error al guardar imagen: $e');
  }
}
