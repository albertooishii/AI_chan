import 'dart:io';
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';
import 'package:path/path.dart' as path;

/// Implementación concreta de operaciones de archivo
class FileOperationsAdapter implements IFileOperationsService {
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
  Future<List<int>?> readFileAsBytes(final String filePath) async {
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
  Future<String?> readFileAsString(final String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        return await file.readAsString();
      }
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> writeFileAsBytes(
    final String filePath,
    final List<int> bytes,
  ) async {
    try {
      final file = File(filePath);
      await createDirectories(path.dirname(filePath));
      await file.writeAsBytes(bytes);
    } on Exception catch (e) {
      throw Exception('Error writing file as bytes: $e');
    }
  }

  @override
  Future<void> writeFileAsString(
    final String filePath,
    final String content,
  ) async {
    try {
      final file = File(filePath);
      await createDirectories(path.dirname(filePath));
      await file.writeAsString(content);
    } on Exception catch (e) {
      throw Exception('Error writing file as string: $e');
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
  Future<int> getFileSize(final String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final stat = file.statSync();
        return stat.size;
      }
      return 0;
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> createDirectories(final String dirPath) async {
    try {
      final directory = Directory(dirPath);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
    } on Exception catch (e) {
      throw Exception('Error creating directories: $e');
    }
  }
}
