import 'dart:io';
import 'package:ai_chan/shared/domain/interfaces/i_file_service.dart';
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;

/// Implementación de infraestructura para operaciones de archivo.
/// Contiene todas las dependencias de dart:io.
class FileService implements IFileService {
  @override
  Future<String> saveFile(
    final List<int> bytes,
    final String filename, {
    final String? directory,
  }) async {
    final dir = directory ?? await getLocalAudioDirectory();
    final file = File('$dir/$filename');

    // Crear directorio si no existe
    file.parent.createSync(recursive: true);

    // Escribir archivo
    await file.writeAsBytes(bytes);

    return file.path;
  }

  @override
  Future<List<int>?> loadFile(final String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        return await file.readAsBytes();
      }
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<bool> fileExists(final String filePath) async {
    return File(filePath).existsSync();
  }

  @override
  Future<void> deleteFile(final String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<String> getLocalAudioDirectory() async {
    final dir = await audio_utils.getLocalAudioDir();
    return dir.path;
  }

  @override
  Future<String> getLocalImageDirectory() async {
    // Implementar según sea necesario
    final audioDir = await getLocalAudioDirectory();
    return audioDir.replaceAll('/audio', '/images');
  }
}
