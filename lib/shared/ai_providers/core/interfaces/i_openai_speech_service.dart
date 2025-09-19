/// Interfaz para servicios de síntesis de voz de OpenAI específica del dominio core
abstract interface class IOpenAISpeechService {
  /// Obtiene la lista de voces disponibles de OpenAI
  Future<List<Map<String, dynamic>>> fetchOpenAIVoices({
    final bool forceRefresh = false,
    final bool femaleOnly = false,
  });

  /// Verifica si el servicio está disponible (tiene API key configurada)
  Future<bool> isAvailable();
}
