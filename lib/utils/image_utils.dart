import 'dart:io';
import 'dart:convert';

/// Guarda una imagen en base64 en el directorio local de imágenes y devuelve la ruta del archivo.
Future<String?> saveBase64ImageToFile(String base64, {String prefix = 'img'}) async {
  try {
    final bytes = base64Decode(base64);
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final absDir = await getLocalImageDir();
    final absFilePath = '${absDir.path}/$fileName';
    final file = await File(absFilePath).writeAsBytes(bytes);
    final exists = await file.exists();
    if (exists) {
      return fileName; // Devuelve solo el nombre de archivo
    } else {
      return null;
    }
  } catch (e) {
    return null;
  }
}

/// Devuelve el directorio local para imágenes del chat (idéntico a ChatProvider)
Future<Directory> getLocalImageDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    // Usar DCIM/AI_chan en móvil
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final dcimDir = Directory('$home/DCIM');
    final aiChanDir = Directory('${dcimDir.path}/AI_chan');
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
  if (Platform.isAndroid || Platform.isIOS) {
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
