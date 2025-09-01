import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Utilidad para limpiar credenciales OAuth de Google de manera manual
/// Útil para resolver problemas de client_id mismatch
class GoogleCredentialsCleaner {
  /// Limpia todas las credenciales OAuth de Google almacenadas
  static Future<void> clearCredentials() async {
    Log.i(
      '🧹 [CLEANER] Iniciando limpieza de credenciales OAuth de Google',
      tag: 'GoogleCleaner',
    );

    try {
      final service = GoogleBackupService(accessToken: null);

      // Diagnosticar antes de limpiar
      final beforeDiagnosis = await service.diagnoseStoredCredentials();
      Log.i('📊 [CLEANER] Estado antes de la limpieza:', tag: 'GoogleCleaner');
      Log.i(
        '  - Credenciales presentes: ${beforeDiagnosis['has_stored_credentials']}',
        tag: 'GoogleCleaner',
      );
      Log.i(
        '  - Client ID original: ${beforeDiagnosis['original_client_id'] ?? 'NO DISPONIBLE'}',
        tag: 'GoogleCleaner',
      );

      // Limpiar credenciales
      await service.clearStoredCredentials();

      // Verificar después de limpiar
      final afterDiagnosis = await service.diagnoseStoredCredentials();
      Log.i('✅ [CLEANER] Estado después de la limpieza:', tag: 'GoogleCleaner');
      Log.i(
        '  - Credenciales presentes: ${afterDiagnosis['has_stored_credentials']}',
        tag: 'GoogleCleaner',
      );

      if (!afterDiagnosis['has_stored_credentials']) {
        Log.i(
          '🎉 [CLEANER] Limpieza exitosa - todas las credenciales han sido eliminadas',
          tag: 'GoogleCleaner',
        );
        Log.i(
          '💡 [CLEANER] La próxima autenticación OAuth almacenará el client_id correcto',
          tag: 'GoogleCleaner',
        );
      } else {
        Log.w(
          '⚠️ [CLEANER] Advertencia: algunas credenciales pueden no haberse eliminado completamente',
          tag: 'GoogleCleaner',
        );
      }
    } catch (e, st) {
      Log.e(
        '❌ [CLEANER] Error durante la limpieza de credenciales: $e',
        tag: 'GoogleCleaner',
        error: e,
        stack: st,
      );
    }
  }

  /// Fuerza una nueva autenticación limpiando credenciales primero
  static Future<Map<String, dynamic>?> forceReauthentication({
    List<String>? scopes,
    String? clientId,
  }) async {
    Log.i(
      '🔄 [CLEANER] Forzando re-autenticación con credenciales limpias',
      tag: 'GoogleCleaner',
    );

    try {
      // Primero limpiar credenciales existentes
      await clearCredentials();

      // Esperar un momento para asegurar que la limpieza se complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Intentar nueva autenticación
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

      Log.i('✅ [CLEANER] Re-autenticación exitosa', tag: 'GoogleCleaner');

      // Verificar que el client_id se almacenó correctamente
      final newDiagnosis = await service.diagnoseStoredCredentials();
      Log.i(
        '📊 [CLEANER] Nueva configuración almacenada:',
        tag: 'GoogleCleaner',
      );
      Log.i(
        '  - Client ID original: ${newDiagnosis['original_client_id']}',
        tag: 'GoogleCleaner',
      );
      Log.i(
        '  - Longitud del client ID: ${newDiagnosis['original_client_id_length']}',
        tag: 'GoogleCleaner',
      );

      return tokenMap;
    } catch (e, st) {
      Log.e(
        '❌ [CLEANER] Error durante re-autenticación: $e',
        tag: 'GoogleCleaner',
        error: e,
        stack: st,
      );
      rethrow;
    }
  }
}
