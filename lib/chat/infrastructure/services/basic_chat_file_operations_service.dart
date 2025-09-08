import 'dart:io';
import '../../domain/interfaces/i_chat_file_operations_service.dart';

/// 🎯 **Basic Chat File Operations Service** - Infrastructure Implementation
///
/// Provides basic file operations for the chat bounded context.
/// This implementation uses Dart's standard File and Directory classes.
///
/// **Clean Architecture Compliance:**
/// ✅ Implements domain interface (IChatFileOperationsService)
/// ✅ Infrastructure layer - can depend on external libraries
/// ✅ No dependencies on domain/application layers
/// ✅ Testable through domain interface
class BasicChatFileOperationsService implements IChatFileOperationsService {
  const BasicChatFileOperationsService();

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
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsBytes();
    } on Exception {
      return null;
    }
  }

  @override
  Future<String?> readFileAsString(final String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsString();
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> writeFileAsBytes(
    final String path,
    final List<int> bytes,
  ) async {
    try {
      final file = File(path);
      await file.writeAsBytes(bytes);
    } on Exception {
      rethrow;
    }
  }

  @override
  Future<void> writeFileAsString(
    final String path,
    final String content,
  ) async {
    try {
      final file = File(path);
      await file.writeAsString(content);
    } on Exception {
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(final String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on Exception {
      rethrow;
    }
  }

  @override
  Future<int> getFileSize(final String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return 0;
      }
      final stat = file.statSync();
      return stat.size;
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> createDirectories(final String path) async {
    try {
      final directory = Directory(path);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
    } on Exception {
      rethrow;
    }
  }
}
