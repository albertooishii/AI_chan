/// Interface para operaciones de archivo en DDD.
/// Permite que la Application Layer maneje archivos sin conocer dart:io.
abstract class IFileService {
  /// Guarda datos binarios en un archivo
  Future<String> saveFile(
    List<int> bytes,
    String filename, {
    String? directory,
  });

  /// Carga datos binarios de un archivo
  Future<List<int>?> loadFile(String filePath);

  /// Verifica si un archivo existe
  Future<bool> fileExists(String filePath);

  /// Elimina un archivo
  Future<void> deleteFile(String filePath);

  /// Obtiene el directorio de audio local
  Future<String> getLocalAudioDirectory();

  /// Obtiene el directorio de imágenes local
  Future<String> getLocalImageDirectory();
}
