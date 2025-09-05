import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';
import 'dart:convert';

/// Servicio de aplicación para operaciones de archivo desde la UI.
/// Proporciona una interfaz limpia para que los widgets accedan a archivos
/// sin violar la arquitectura DDD.
class FileUIService {
  final IFileOperationsService _fileOperations;

  const FileUIService(this._fileOperations);

  /// Verifica si un archivo existe
  Future<bool> fileExists(String path) async {
    try {
      return await _fileOperations.fileExists(path);
    } catch (e) {
      return false;
    }
  }

  /// Obtiene el tamaño de un archivo en bytes
  Future<int> getFileSize(String path) async {
    return await _fileOperations.getFileSize(path);
  }

  /// Lee el contenido de un archivo como string
  Future<String?> readFileAsString(String path) async {
    return await _fileOperations.readFileAsString(path);
  }

  /// Lee el contenido de un archivo como bytes
  Future<List<int>?> readFileAsBytes(String path) async {
    return await _fileOperations.readFileAsBytes(path);
  }

  /// Escribe contenido string a un archivo
  Future<void> writeFileAsString(String path, String content) async {
    await _fileOperations.writeFileAsString(path, content);
  }

  /// Escribe contenido bytes a un archivo
  Future<void> writeFileAsBytes(String path, List<int> bytes) async {
    await _fileOperations.writeFileAsBytes(path, bytes);
  }

  /// Elimina un archivo
  Future<void> deleteFile(String path) async {
    await _fileOperations.deleteFile(path);
  }

  /// Crea directorios necesarios
  Future<void> createDirectories(String path) async {
    await _fileOperations.createDirectories(path);
  }

  /// Obtiene la extensión de un archivo
  String getFileExtension(String filePath) {
    final lastDot = filePath.lastIndexOf('.');
    if (lastDot == -1) return '';
    return filePath.substring(lastDot);
  }

  /// Obtiene el nombre del archivo sin la ruta
  String getFileName(String filePath) {
    return filePath.split('/').last;
  }

  /// Obtiene el directorio padre de un archivo
  String getDirectoryPath(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return '';
    return filePath.substring(0, lastSlash);
  }

  /// Combina rutas de directorio
  String joinPath(String dir, String fileName) {
    return dir.endsWith('/') ? '$dir$fileName' : '$dir/$fileName';
  }

  /// Guarda una imagen en base64 como archivo
  Future<String?> saveBase64Image(
    String base64, {
    String prefix = 'img',
  }) async {
    try {
      final bytes = base64Decode(base64);
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Crear un path temporal, la implementación concreta manejará el directorio
      final imagePath = 'temp/$fileName';

      await _fileOperations.createDirectories(getDirectoryPath(imagePath));
      await _fileOperations.writeFileAsBytes(imagePath, bytes);

      return fileName;
    } catch (e) {
      return null;
    }
  }

  /// Crea un archivo temporal desde bytes y devuelve su path
  Future<String> createTempFileFromBytes(
    List<int> bytes,
    String fileName,
  ) async {
    // Crear un path temporal único
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '/tmp/ai_chan_temp_${timestamp}_$fileName';

    await _fileOperations.writeFileAsBytes(tempPath, bytes);
    return tempPath;
  }
}
