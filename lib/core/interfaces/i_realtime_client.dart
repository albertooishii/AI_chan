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
}
