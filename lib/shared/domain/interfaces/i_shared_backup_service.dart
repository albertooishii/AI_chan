/// Shared Backup Service - Domain Interface
/// Interfaz compartida para operaciones de backup que pueden ser utilizadas
/// por diferentes contextos sin violar arquitectura DDD.
abstract class ISharedBackupService {
  /// Perform Google Drive backup
  Future<void> performGoogleDriveBackup();

  /// Perform local backup
  Future<void> performLocalBackup();

  /// Get backup status
  Future<String> getBackupStatus();

  /// Check if backup is available
  bool isBackupAvailable();
}
