/// Interface para operaciones de archivo siguiendo DDD
/// Abstrae las operaciones de archivo del Application Layer
abstract class IFileOperationsService {
  /// Verifica si un archivo existe
  Future<bool> fileExists(String path);

  /// Lee el contenido de un archivo como bytes
  Future<List<int>?> readFileAsBytes(String path);

  /// Lee el contenido de un archivo como string
  Future<String?> readFileAsString(String path);

  /// Escribe bytes a un archivo
  Future<void> writeFileAsBytes(String path, List<int> bytes);

  /// Escribe string a un archivo
  Future<void> writeFileAsString(String path, String content);

  /// Elimina un archivo
  Future<void> deleteFile(String path);

  /// Obtiene el tamaño de un archivo
  Future<int> getFileSize(String path);

  /// Crea directorios si no existen
  Future<void> createDirectories(String path);
}
