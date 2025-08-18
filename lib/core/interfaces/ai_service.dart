abstract class IAIService {
  /// Envía un prompt/historia y devuelve la respuesta cruda del proveedor.
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, dynamic>> messages,
    Map<String, dynamic>? options,
  });

  /// Lista de modelos o capacidades disponibles.
  Future<List<String>> getAvailableModels();
}
