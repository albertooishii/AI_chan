/// Interfaz para exportar datos de chat en el contexto de onboarding
/// Abstrae las operaciones de exportación sin depender del bounded context de chat
abstract interface class IChatExportService {
  /// Guarda una exportación de chat
  /// [exportData] Los datos de exportación en formato Map
  Future<void> saveExport(final Map<String, dynamic> exportData);

  /// Obtiene una exportación de chat
  /// Retorna null si no existe
  Future<Map<String, dynamic>?> getExport();

  /// Verifica si existe una exportación
  Future<bool> hasExport();
}
