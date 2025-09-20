import 'dart:io';
import 'package:ai_chan/shared.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Implementación concreta del servicio de archivos
class FileServiceAdapter implements IFileService {
  @override
  Future<String> saveFile(
    final List<int> bytes,
    final String filename, {
    final String? directory,
  }) async {
    try {
      final dir = directory ?? await getLocalAudioDirectory();
      await _ensureDirectoryExists(dir);

      final filePath = path.join(dir, filename);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return filePath;
    } on Exception catch (e) {
      throw Exception('Error saving file: $e');
    }
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
    try {
      final file = File(filePath);
      return file.existsSync();
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> deleteFile(final String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
      }
    } on Exception catch (e) {
      throw Exception('Error deleting file: $e');
    }
  }

  @override
  Future<String> getLocalAudioDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = path.join(appDir.path, 'audio');
      await _ensureDirectoryExists(audioDir);
      return audioDir;
    } on Exception catch (e) {
      throw Exception('Error getting audio directory: $e');
    }
  }

  @override
  Future<String> getLocalImageDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = path.join(appDir.path, 'images');
      await _ensureDirectoryExists(imageDir);
      return imageDir;
    } on Exception catch (e) {
      throw Exception('Error getting image directory: $e');
    }
  }

  /// Asegura que el directorio existe
  Future<void> _ensureDirectoryExists(final String dirPath) async {
    final directory = Directory(dirPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
  }
}
