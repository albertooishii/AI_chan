import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// import eliminado: image_gallery_saver_plus

/// Guarda una imagen en base64 en el directorio local de imágenes y devuelve la ruta del archivo.
Future<String?> saveBase64ImageToFile(String base64, {String prefix = 'img'}) async {
  try {
    final bytes = base64Decode(base64);
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final absDir = await getLocalImageDir();
    final absFilePath = '${absDir.path}/$fileName';
    debugPrint('[AI-chan][Image] Guardando imagen en: $absFilePath');
    final file = await File(absFilePath).writeAsBytes(bytes);
    final exists = await file.exists();
    if (exists) {
      debugPrint('[AI-chan][Image] Imagen guardada correctamente en: $absFilePath');
      return fileName;
    } else {
      debugPrint('[AI-chan][Image] Error: El archivo no existe tras guardar.');
      return null;
    }
  } catch (e) {
    debugPrint('[AI-chan][Image] Error al guardar imagen: $e');
    return null;
  }
}

/// Devuelve el directorio local para imágenes del chat (idéntico a ChatProvider)
Future<Directory> getLocalImageDir() async {
  if (Platform.isAndroid) {
    // Guardar en /storage/emulated/0/Pictures/AI_chan (recomendado por Android moderno)
    final picturesPath = '/storage/emulated/0/Pictures/AI_chan';
    final aiChanDir = Directory(picturesPath);
    if (!await aiChanDir.exists()) {
      await aiChanDir.create(recursive: true);
    }
    return aiChanDir;
  } else if (Platform.isIOS) {
    final docsDir = await getApplicationDocumentsDirectory();
    final aiChanDir = Directory('${docsDir.path}/AI_chan');
    if (!await aiChanDir.exists()) {
      await aiChanDir.create(recursive: true);
    }
    return aiChanDir;
  } else {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    Directory? downloadsDir;
    final descargas = Directory('$home/Descargas');
    final downloads = Directory('$home/Downloads');
    if (await descargas.exists()) {
      downloadsDir = descargas;
    } else if (await downloads.exists()) {
      downloadsDir = downloads;
    } else {
      downloadsDir = downloads;
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
    }
    final aiChanDir = Directory('${downloadsDir.path}/AI_chan');
    if (!await aiChanDir.exists()) {
      await aiChanDir.create(recursive: true);
    }
    return aiChanDir;
  }
}

/// Devuelve la ruta relativa para guardar imágenes
Future<String> getRelativeImageDir() async {
  if (Platform.isAndroid) {
    return 'Pictures/AI_chan';
  } else if (Platform.isIOS) {
    return 'DCIM/AI_chan';
  } else {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (Directory('$home/Descargas').existsSync()) {
      return 'Descargas/AI_chan';
    } else {
      return 'Downloads/AI_chan';
    }
  }
}
