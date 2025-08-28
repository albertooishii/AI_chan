import 'dart:io';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/core/config.dart';

/// Guarda una imagen en base64 en el directorio de documentos de la app
/// bajo la carpeta `images`.
Future<String?> saveBase64ImageToFile(String base64, {String prefix = 'img'}) async {
  try {
    final bytes = base64Decode(base64);
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final absDir = await getLocalImageDir();
    final absFilePath = '${absDir.path}/$fileName';
    Log.d('[Image] Guardando imagen en: $absFilePath', tag: 'IMAGE_UTILS');
    final file = await File(absFilePath).writeAsBytes(bytes);
    final exists = await file.exists();
    if (exists) {
      Log.i('[Image] Imagen guardada correctamente en: $absFilePath', tag: 'IMAGE_UTILS');
      return fileName;
    } else {
      Log.w('[Image] Error: El archivo no existe tras guardar.', tag: 'IMAGE_UTILS');
      return null;
    }
  } catch (e) {
    final isExpected = e is StateError || e is FormatException;
    if (isExpected) {
      Log.w('[Image] No se pudo guardar imagen (esperado): ${e.toString()}', tag: 'IMAGE_UTILS');
    } else {
      Log.e('[Image] Error al guardar imagen', tag: 'IMAGE_UTILS', error: e);
    }
    return null;
  }
}

/// Devuelve el directorio local para imágenes: app_documents/images
Future<Directory> getLocalImageDir() async {
  // Allow tests to override the image directory using a test-only key.
  final testOverride = Config.get('TEST_IMAGE_DIR', '').trim();
  if (testOverride.isNotEmpty) {
    final dir = Directory(testOverride);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  if (kIsWeb) {
    // En web no hay un directorio real; usar carpeta virtual en memoria o nombre simbólico.
    return Directory('AI_chan_images');
  }

  // Prefer OS-specific Application Support on desktop so the app doesn't
  // create loose folders under the user's Documents directory. On mobile
  // and web keep using the documents directory (mobile uses app-private
  // Documents; web uses virtual folder name).
  final appDoc = (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();

  final imagesDir = Directory('${appDoc.path}/AI_chan/images');
  if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
  return imagesDir;
}

/// Ruta relativa usada internamente para presentar/serializar paths (simple nombre)
Future<String> getRelativeImageDir() async {
  return 'AI_chan/images';
}
