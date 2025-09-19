import 'package:ai_chan/shared.dart';

/// Servicio de aplicación para operaciones de archivo desde la UI.
/// Proporciona una interfaz limpia para que los widgets accedan a archivos
/// sin violar la arquitectura DDD.
class FileUIService {
  const FileUIService(this._fileOperations);
  final IFileOperationsService _fileOperations;

  /// Verifica si un archivo existe
  Future<bool> fileExists(final String path) async {
    try {
      return await _fileOperations.fileExists(path);
    } on Exception {
      return false;
    }
  }

  /// Obtiene el tamaño de un archivo en bytes
  Future<int> getFileSize(final String path) async {
    return await _fileOperations.getFileSize(path);
  }

  /// Lee el contenido de un archivo como string
  Future<String?> readFileAsString(final String path) async {
    return await _fileOperations.readFileAsString(path);
  }

  /// Lee el contenido de un archivo como bytes
  Future<List<int>?> readFileAsBytes(final String path) async {
    return await _fileOperations.readFileAsBytes(path);
  }

  /// Escribe contenido string a un archivo
  Future<void> writeFileAsString(
    final String path,
    final String content,
  ) async {
    await _fileOperations.writeFileAsString(path, content);
  }

  /// Escribe contenido bytes a un archivo
  Future<void> writeFileAsBytes(
    final String path,
    final List<int> bytes,
  ) async {
    await _fileOperations.writeFileAsBytes(path, bytes);
  }

  /// Elimina un archivo
  Future<void> deleteFile(final String path) async {
    await _fileOperations.deleteFile(path);
  }

  /// Crea directorios necesarios
  Future<void> createDirectories(final String path) async {
    await _fileOperations.createDirectories(path);
  }

  /// Obtiene la extensión de un archivo
  String getFileExtension(final String filePath) {
    final lastDot = filePath.lastIndexOf('.');
    if (lastDot == -1) return '';
    return filePath.substring(lastDot);
  }

  /// Obtiene el nombre del archivo sin la ruta
  String getFileName(final String filePath) {
    return filePath.split('/').last;
  }

  /// Obtiene el directorio padre de un archivo
  String getDirectoryPath(final String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return '';
    return filePath.substring(0, lastSlash);
  }

  /// Combina rutas de directorio
  String joinPath(final String dir, final String fileName) {
    return dir.endsWith('/') ? '$dir$fileName' : '$dir/$fileName';
  }

  /// Guarda una imagen en base64 como archivo en el directorio correcto de la aplicación
  Future<String?> saveBase64Image(
    final String base64, {
    final String prefix = 'img',
  }) async {
    // Delegar al servicio de imagen que maneja correctamente el directorio de la aplicación
    return await ImagePersistenceService.instance.saveBase64Image(
      base64,
      prefix: prefix,
    );
  }

  /// Crea un archivo temporal desde bytes y devuelve su path
  Future<String> createTempFileFromBytes(
    final List<int> bytes,
    final String fileName,
  ) async {
    // Crear un path temporal único
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '/tmp/ai_chan_temp_${timestamp}_$fileName';

    await _fileOperations.writeFileAsBytes(tempPath, bytes);
    return tempPath;
  }
}
