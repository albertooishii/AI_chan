import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// Guarda una imagen en base64 en el directorio local de imágenes y devuelve la ruta del archivo.
Future<String?> saveBase64ImageToFile(String base64, {String prefix = 'img'}) async {
  try {
    final bytes = base64Decode(base64);
    final dir = await getLocalImageDir();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = '${dir.path}/$fileName';
    final file = await File(filePath).writeAsBytes(bytes);
    final exists = await file.exists();
    if (exists) {
      return file.path;
    } else {
      return null;
    }
  } catch (e) {
    return null;
  }
}

/// Devuelve el directorio local para imágenes del chat (idéntico a ChatProvider)
Future<Directory> getLocalImageDir() async {
  if (Platform.isAndroid) {
    final dir = await getApplicationDocumentsDirectory();
    final aiChanDir = Directory('${dir.path}/AI_chan');
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
