abstract class IAIService {
  /// Envía un prompt/historia y devuelve la respuesta cruda del proveedor.
  Future<Map<String, dynamic>> sendMessage({
    required final List<Map<String, dynamic>> messages,
    final Map<String, dynamic>? options,
  });

  /// Lista de modelos o capacidades disponibles.
  Future<List<String>> getAvailableModels();

  /// (Opcional) Generación de audio TTS por el proveedor.
  /// Devuelve un path de archivo o null si no soportado.
  Future<String?> textToSpeech(
    final String text, {
    final String voice,
    final Map<String, dynamic>? options,
  });
}
