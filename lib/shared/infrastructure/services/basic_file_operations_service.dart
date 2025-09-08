import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';
import 'package:ai_chan/chat/infrastructure/services/basic_chat_file_operations_service.dart';

/// 🎯 **Basic File Operations Service** - Infrastructure Implementation for Shared Context
///
/// Delegates to BasicChatFileOperationsService to maintain consistency.
/// This ensures both shared and chat contexts use the same file operations implementation.
///
/// **Clean Architecture Compliance:**
/// ✅ Implements shared domain interface (IFileOperationsService)
/// ✅ Delegates to chat infrastructure implementation
/// ✅ Maintains single responsibility and DRY principle
/// ✅ Infrastructure layer - can depend on other infrastructure
class BasicFileOperationsService implements IFileOperationsService {
  const BasicFileOperationsService();

  // Singleton instance for consistency
  static final BasicChatFileOperationsService _chatFileOps =
      const BasicChatFileOperationsService();

  @override
  Future<bool> fileExists(final String path) async {
    return _chatFileOps.fileExists(path);
  }

  @override
  Future<List<int>?> readFileAsBytes(final String path) async {
    return _chatFileOps.readFileAsBytes(path);
  }

  @override
  Future<String?> readFileAsString(final String path) async {
    return _chatFileOps.readFileAsString(path);
  }

  @override
  Future<void> writeFileAsBytes(
    final String path,
    final List<int> bytes,
  ) async {
    return _chatFileOps.writeFileAsBytes(path, bytes);
  }

  @override
  Future<void> writeFileAsString(
    final String path,
    final String content,
  ) async {
    return _chatFileOps.writeFileAsString(path, content);
  }

  @override
  Future<void> deleteFile(final String path) async {
    return _chatFileOps.deleteFile(path);
  }

  @override
  Future<int> getFileSize(final String path) async {
    return _chatFileOps.getFileSize(path);
  }

  @override
  Future<void> createDirectories(final String path) async {
    return _chatFileOps.createDirectories(path);
  }
}
