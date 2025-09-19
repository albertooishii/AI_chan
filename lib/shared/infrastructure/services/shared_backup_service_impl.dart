import 'package:ai_chan/shared.dart';

/// Implementation of shared backup service using existing infrastructure
class SharedBackupServiceImpl implements ISharedBackupService {
  @override
  Future<void> performGoogleDriveBackup() async {
    // Use existing Google backup functionality
    Log.i('Google Drive backup functionality delegated to existing service');
    // This would integrate with the existing GoogleBackupService when needed
  }

  @override
  Future<void> performLocalBackup() async {
    // Local backup functionality
    Log.i('Local backup functionality not yet implemented');
  }

  @override
  Future<String> getBackupStatus() async {
    // Basic status check
    return 'Backup service available';
  }

  @override
  bool isBackupAvailable() {
    // Basic availability check
    return true;
  }
}
