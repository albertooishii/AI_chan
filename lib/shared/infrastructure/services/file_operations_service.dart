import 'dart:io';
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';

/// Implementación concreta del servicio de operaciones de archivo
/// Encapsula todas las operaciones dart:io en Infrastructure Layer
class FileOperationsService implements IFileOperationsService {
  @override
  Future<bool> fileExists(final String path) async {
    try {
      final file = File(path);
      return file.existsSync();
    } on Exception {
      return false;
    }
  }

  @override
  Future<List<int>?> readFileAsBytes(final String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return await file.readAsBytes();
      }
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<String?> readFileAsString(final String path) async {
    try {
      final file = File(path);
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
    final String path,
    final List<int> bytes,
  ) async {
    final file = File(path);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeFileAsString(
    final String path,
    final String content,
  ) async {
    final file = File(path);
    file.parent.createSync(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> deleteFile(final String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<int> getFileSize(final String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return await file.length();
      }
      return 0;
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> createDirectories(final String path) async {
    final directory = Directory(path);
    directory.createSync(recursive: true);
  }
}
