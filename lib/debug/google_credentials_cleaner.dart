import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Utility to clean Google OAuth credentials
class GoogleCredentialsCleaner {
  /// Clear all stored Google OAuth credentials
  static Future<void> clearCredentials() async {
    Log.i('Clearing Google OAuth credentials', tag: 'GoogleCleaner');

    try {
      final service = GoogleBackupService(accessToken: null);

      final beforeDiagnosis = await service.diagnoseStoredCredentials();
      Log.i(
        'Before cleanup - stored: ${beforeDiagnosis['has_stored_credentials']}',
        tag: 'GoogleCleaner',
      );

      await service.clearStoredCredentials();

      final afterDiagnosis = await service.diagnoseStoredCredentials();
      Log.i(
        'After cleanup - stored: ${afterDiagnosis['has_stored_credentials']}',
        tag: 'GoogleCleaner',
      );

      if (!afterDiagnosis['has_stored_credentials']) {
        Log.i('Credentials cleared successfully', tag: 'GoogleCleaner');
      } else {
        Log.w(
          'Some credentials may not have been cleared',
          tag: 'GoogleCleaner',
        );
      }
    } catch (e, st) {
      Log.e(
        'Error clearing credentials: $e',
        tag: 'GoogleCleaner',
        error: e,
        stack: st,
      );
    }
  }

  /// Force reauthentication by clearing credentials first
  static Future<Map<String, dynamic>?> forceReauthentication({
    List<String>? scopes,
    String? clientId,
  }) async {
    Log.i(
      'Forcing reauthentication with clean credentials',
      tag: 'GoogleCleaner',
    );

    try {
      await clearCredentials();
      await Future.delayed(const Duration(milliseconds: 500));

      final service = GoogleBackupService(accessToken: null);
      final tokenMap = await service.linkAccount(
        clientId: clientId,
        scopes:
            scopes ??
            [
              'openid',
              'email',
              'profile',
              'https://www.googleapis.com/auth/drive.appdata',
            ],
      );

      Log.i('Reauthentication successful', tag: 'GoogleCleaner');

      final newDiagnosis = await service.diagnoseStoredCredentials();
      Log.i(
        'New client ID stored: ${newDiagnosis['original_client_id']}',
        tag: 'GoogleCleaner',
      );

      return tokenMap;
    } catch (e, st) {
      Log.e(
        'Reauthentication error: $e',
        tag: 'GoogleCleaner',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }
}
