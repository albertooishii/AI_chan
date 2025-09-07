import 'package:ai_chan/chat/domain/interfaces/i_backup_service.dart';

/// Basic implementation of IBackupService for dependency injection
class BasicBackupService implements IBackupService {
  @override
  Future<bool> isAvailable() async {
    return false; // Basic implementation always returns false
  }

  @override
  Future<void> uploadAfterChanges({
    required final Map<String, dynamic> profile,
    required final List<Map<String, dynamic>> messages,
    required final List<Map<String, dynamic>> timeline,
    required final bool isLinked,
  }) async {
    // Basic implementation does nothing
  }

  @override
  Future<List<Map<String, dynamic>>> listBackups() async {
    return [];
  }

  @override
  Future<bool> refreshAccessToken() async {
    return false;
  }
}
