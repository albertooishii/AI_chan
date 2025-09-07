/// 🎯 **Chat Backup Utils Service Interface** - Domain Abstraction for Backup Operations
///
/// Defines the contract for backup utility operations within the chat bounded context.
/// This ensures bounded context isolation while providing backup functionality.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatBackupUtilsService {
  /// Uploads backup automatically
  Future<void> uploadBackup(final String backupPath);

  /// Validates backup integrity
  Future<bool> validateBackup(final String backupPath);

  /// Gets backup file size
  Future<int> getBackupSize(final String backupPath);
}
