abstract class IRealtimeClient {
  bool get isConnected;

  /// Send a short text message directly to the realtime channel (useful to force
  /// the model to produce a spoken response without STT). Optional for providers.
  void sendText(String text);

  Future<void> connect({
    required String systemPrompt,
    String voice,
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  });

  void updateVoice(String voice);

  void appendAudio(List<int> bytes);

  /// Provider-agnostic request: ask for a response (audio/text)
  void requestResponse({bool audio = true, bool text = true});

  /// Commit any pending local audio for transcription immediately.
  Future<void> commitPendingAudio();

  Future<void> close();

  // Nuevas funcionalidades opcionales para gpt-realtime (implementadas solo en OpenAI)

  /// Envía una imagen junto con texto opcional (solo OpenAI gpt-realtime)
  void sendImageWithText({
    required String imageBase64,
    String? text,
    String imageFormat = 'png',
  }) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Configura herramientas/funciones para el modelo (solo OpenAI gpt-realtime)
  void configureTools(List<Map<String, dynamic>> tools) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Responde a una llamada de función (solo OpenAI gpt-realtime)
  void sendFunctionCallOutput({
    required String callId,
    required String output,
  }) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Cancela la respuesta actual con control avanzado (solo OpenAI gpt-realtime)
  void cancelResponse({String? itemId, int? sampleCount}) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }
}
