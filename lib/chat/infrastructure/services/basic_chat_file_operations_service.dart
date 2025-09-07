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
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error checking file existence: $path - $e');
      return false;
    }
  }

  @override
  Future<List<int>?> readFileAsBytes(final String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        print('⚠️ [ChatFileOps] File does not exist: $path');
        return null;
      }
      return await file.readAsBytes();
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error reading file as bytes: $path - $e');
      return null;
    }
  }

  @override
  Future<String?> readFileAsString(final String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        print('⚠️ [ChatFileOps] File does not exist: $path');
        return null;
      }
      return await file.readAsString();
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error reading file as string: $path - $e');
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
      print('✅ [ChatFileOps] File written successfully: $path');
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error writing file as bytes: $path - $e');
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
      print('✅ [ChatFileOps] File written successfully: $path');
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error writing file as string: $path - $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(final String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
        print('✅ [ChatFileOps] File deleted successfully: $path');
      } else {
        print('⚠️ [ChatFileOps] File does not exist, cannot delete: $path');
      }
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error deleting file: $path - $e');
      rethrow;
    }
  }

  @override
  Future<int> getFileSize(final String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        print('⚠️ [ChatFileOps] File does not exist: $path');
        return 0;
      }
      final stat = await file.stat();
      return stat.size;
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error getting file size: $path - $e');
      return 0;
    }
  }

  @override
  Future<void> createDirectories(final String path) async {
    try {
      final directory = Directory(path);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
        print('✅ [ChatFileOps] Directories created successfully: $path');
      } else {
        print('ℹ️ [ChatFileOps] Directories already exist: $path');
      }
    } on Exception catch (e) {
      print('❌ [ChatFileOps] Error creating directories: $path - $e');
      rethrow;
    }
  }
}
