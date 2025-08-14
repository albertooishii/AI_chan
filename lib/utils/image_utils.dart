import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// Rutas ahora configurables vía .env: IMAGE_DIR_ANDROID, IMAGE_DIR_IOS, IMAGE_DIR_DESKTOP, IMAGE_DIR_WEB

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

/// Devuelve el directorio local para imágenes del chat usando exclusivamente las claves de `.env`.
/// Lanza un error si no está configurado.
Future<Directory> getLocalImageDir() async {
  if (kIsWeb) {
    final webDir = dotenv.env['IMAGE_DIR_WEB'];
    if (webDir == null || webDir.trim().isEmpty) {
      throw StateError('IMAGE_DIR_WEB no está configurado en .env');
    }
    return Directory(webDir.trim());
  }

  String? configured;
  if (Platform.isAndroid) {
    configured = dotenv.env['IMAGE_DIR_ANDROID'];
  } else if (Platform.isIOS) {
    configured = dotenv.env['IMAGE_DIR_IOS'];
  } else {
    configured = dotenv.env['IMAGE_DIR_DESKTOP'];
  }

  if (configured == null || configured.trim().isEmpty) {
    throw StateError('IMAGE_DIR no está configurado en .env para esta plataforma');
  }

  final dir = Directory(configured.trim());
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Devuelve la ruta relativa para guardar imágenes
Future<String> getRelativeImageDir() async {
  if (Platform.isAndroid) {
    final cfg = dotenv.env['IMAGE_DIR_ANDROID'];
    if (cfg == null || cfg.trim().isEmpty) throw StateError('IMAGE_DIR_ANDROID no está en .env');
    return cfg.trim();
  } else if (Platform.isIOS) {
    final cfg = dotenv.env['IMAGE_DIR_IOS'];
    if (cfg == null || cfg.trim().isEmpty) throw StateError('IMAGE_DIR_IOS no está en .env');
    return cfg.trim();
  } else {
    // Desktop: always point to $HOME/AI_chan/images dynamically
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) throw StateError('No se pudo determinar el home del usuario');
    return 'AI_chan/images';
  }
}
