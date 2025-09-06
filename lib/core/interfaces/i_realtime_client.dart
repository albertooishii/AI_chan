abstract class IRealtimeClient {
  bool get isConnected;

  /// Send a short text message directly to the realtime channel (useful to force
  /// the model to produce a spoken response without STT). Optional for providers.
  void sendText(final String text);

  Future<void> connect({
    required final String systemPrompt,
    final String voice,
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  });

  void updateVoice(final String voice);

  void appendAudio(final List<int> bytes);

  /// Provider-agnostic request: ask for a response (audio/text)
  void requestResponse({final bool audio = true, final bool text = true});

  /// Commit any pending local audio for transcription immediately.
  Future<void> commitPendingAudio();

  Future<void> close();

  // Nuevas funcionalidades opcionales para gpt-realtime (implementadas solo en OpenAI)

  /// Envía una imagen junto con texto opcional (solo OpenAI gpt-realtime)
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Configura herramientas/funciones para el modelo (solo OpenAI gpt-realtime)
  void configureTools(final List<Map<String, dynamic>> tools) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Responde a una llamada de función (solo OpenAI gpt-realtime)
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }

  /// Cancela la respuesta actual con control avanzado (solo OpenAI gpt-realtime)
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // Implementación por defecto vacía para compatibilidad con otros providers
  }
}
