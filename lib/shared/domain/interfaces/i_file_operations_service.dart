/// Interface para operaciones de archivo siguiendo DDD
/// Abstrae las operaciones de archivo del Application Layer
abstract class IFileOperationsService {
  /// Verifica si un archivo existe
  Future<bool> fileExists(final String path);

  /// Lee el contenido de un archivo como bytes
  Future<List<int>?> readFileAsBytes(final String path);

  /// Lee el contenido de un archivo como string
  Future<String?> readFileAsString(final String path);

  /// Escribe bytes a un archivo
  Future<void> writeFileAsBytes(final String path, final List<int> bytes);

  /// Escribe string a un archivo
  Future<void> writeFileAsString(final String path, final String content);

  /// Elimina un archivo
  Future<void> deleteFile(final String path);

  /// Obtiene el tamaño de un archivo
  Future<int> getFileSize(final String path);

  /// Crea directorios si no existen
  Future<void> createDirectories(final String path);
}
