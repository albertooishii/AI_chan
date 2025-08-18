abstract class ISttService {
  /// Transcribe un archivo de audio y devuelve el texto transcrito.
  Future<String?> transcribeFile({required String filePath, Map<String, dynamic>? options});
}
