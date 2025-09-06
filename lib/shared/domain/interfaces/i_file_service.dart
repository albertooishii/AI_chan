/// Interface para operaciones de archivo en DDD.
/// Permite que la Application Layer maneje archivos sin conocer dart:io.
abstract class IFileService {
  /// Guarda datos binarios en un archivo
  Future<String> saveFile(
    final List<int> bytes,
    final String filename, {
    final String? directory,
  });

  /// Carga datos binarios de un archivo
  Future<List<int>?> loadFile(final String filePath);

  /// Verifica si un archivo existe
  Future<bool> fileExists(final String filePath);

  /// Elimina un archivo
  Future<void> deleteFile(final String filePath);

  /// Obtiene el directorio de audio local
  Future<String> getLocalAudioDirectory();

  /// Obtiene el directorio de imágenes local
  Future<String> getLocalImageDirectory();
}
