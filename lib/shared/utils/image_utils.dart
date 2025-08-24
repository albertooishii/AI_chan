import 'dart:io';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/core/config.dart';
// Rutas ahora configurables vía .env: IMAGE_DIR_ANDROID, IMAGE_DIR_IOS, IMAGE_DIR_DESKTOP, IMAGE_DIR_WEB

/// Guarda una imagen en base64 en el directorio local de imágenes y devuelve la ruta del archivo.
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
    // Algunas condiciones son esperadas en tests (p.ej. IMAGE_DIR no configurado
    // o base64 no válido). Registrar como warn para no marcar tests como fallos
    // visibles. En caso de error inesperado, seguir registrando la excepción.
    final isExpected = e is StateError || e is FormatException;
    if (isExpected) {
      Log.w('[Image] No se pudo guardar imagen (esperado): ${e.toString()}', tag: 'IMAGE_UTILS');
    } else {
      Log.e('[Image] Error al guardar imagen', tag: 'IMAGE_UTILS', error: e);
    }
    return null;
  }
}

/// Devuelve el directorio local para imágenes del chat usando exclusivamente las claves de `.env`.
/// Lanza un error si no está configurado.
Future<Directory> getLocalImageDir() async {
  if (kIsWeb) {
    final webDir = Config.get('IMAGE_DIR_WEB', '');
    if (webDir.trim().isEmpty) {
      throw StateError('IMAGE_DIR_WEB no está configurado en .env');
    }
    return Directory(webDir.trim());
  }

  String? configured;
  if (Platform.isAndroid) {
    configured = Config.get('IMAGE_DIR_ANDROID', '');
  } else if (Platform.isIOS) {
    configured = Config.get('IMAGE_DIR_IOS', '');
  } else {
    configured = Config.get('IMAGE_DIR_DESKTOP', '');
  }

  if (configured.trim().isEmpty) {
    throw StateError('IMAGE_DIR no está configurado en .env para esta plataforma');
  }

  // Expandir '~' a la ruta HOME y resolver rutas relativas para escritorio
  var cfg = configured.trim();
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (cfg.startsWith('~')) {
    if (home.isEmpty) {
      throw StateError('No se pudo determinar HOME para expandir ~ en IMAGE_DIR_DESKTOP');
    }
    cfg = cfg.replaceFirst('~', home);
  } else if (!cfg.startsWith('/') && home.isNotEmpty) {
    // Ruta relativa -> interpretarla dentro de $HOME
    cfg = '$home/$cfg';
  }

  final dir = Directory(cfg);
  if (!(await dir.exists())) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Devuelve la ruta relativa para guardar imágenes
Future<String> getRelativeImageDir() async {
  if (Platform.isAndroid) {
    final cfg = Config.get('IMAGE_DIR_ANDROID', '');
    if (cfg.trim().isEmpty) {
      throw StateError('IMAGE_DIR_ANDROID no está en .env');
    }
    return cfg.trim();
  } else if (Platform.isIOS) {
    final cfg = Config.get('IMAGE_DIR_IOS', '');
    if (cfg.trim().isEmpty) throw StateError('IMAGE_DIR_IOS no está en .env');
    return cfg.trim();
  } else {
    // Desktop: always point to $HOME/AI_chan/images dynamically
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) {
      throw StateError('No se pudo determinar el home del usuario');
    }
    return 'AI_chan/images';
  }
}
