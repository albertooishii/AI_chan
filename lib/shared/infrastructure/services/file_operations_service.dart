import 'dart:io';
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';

/// Implementación concreta del servicio de operaciones de archivo
/// Encapsula todas las operaciones dart:io en Infrastructure Layer
class FileOperationsService implements IFileOperationsService {
  @override
  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> readFileAsString(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeFileAsBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeFileAsString(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<int> getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<void> createDirectories(String path) async {
    final directory = Directory(path);
    await directory.create(recursive: true);
  }
}
