/// Secure Storage Service - Domain Port
/// Interfaz para almacenamiento seguro de datos sensibles.
/// Abstrae el almacenamiento seguro de credenciales y datos sensibles.
abstract class ISecureStorageService {
  /// Lee un valor del almacenamiento seguro.
  Future<String?> read(final String key);

  /// Escribe un valor en el almacenamiento seguro.
  Future<void> write(final String key, final String value);

  /// Elimina un valor del almacenamiento seguro.
  Future<void> delete(final String key);

  /// Verifica si una clave existe en el almacenamiento seguro.
  Future<bool> containsKey(final String key);
}
