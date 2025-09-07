/// Backup Service - Domain Port
/// Interfaz para servicios de backup y restauración.
/// Abstrae la funcionalidad de backup a servicios externos como Google Drive.
abstract class IBackupService {
  /// Verifica si el servicio de backup está disponible y configurado.
  Future<bool> isAvailable();

  /// Sube un backup después de cambios significativos.
  Future<void> uploadAfterChanges({
    required final Map<String, dynamic> profile,
    required final List<Map<String, dynamic>> messages,
    required final List<Map<String, dynamic>> timeline,
    required final bool isLinked,
  });

  /// Lista los backups disponibles.
  Future<List<Map<String, dynamic>>> listBackups();

  /// Refresca el token de acceso si es necesario.
  Future<bool> refreshAccessToken();
}
