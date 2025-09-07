/// 🎯 **Chat File Operations Service Interface** - Domain Abstraction for File Operations
///
/// Defines the contract for file operations within the chat bounded context.
/// This ensures bounded context isolation while providing necessary file functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatFileOperationsService {
  /// Verifies if a file exists
  Future<bool> fileExists(final String path);

  /// Reads file content as bytes
  Future<List<int>?> readFileAsBytes(final String path);

  /// Reads file content as string
  Future<String?> readFileAsString(final String path);

  /// Writes bytes to a file
  Future<void> writeFileAsBytes(final String path, final List<int> bytes);

  /// Writes string to a file
  Future<void> writeFileAsString(final String path, final String content);

  /// Deletes a file
  Future<void> deleteFile(final String path);

  /// Gets file size
  Future<int> getFileSize(final String path);

  /// Creates directories if they don't exist
  Future<void> createDirectories(final String path);
}
