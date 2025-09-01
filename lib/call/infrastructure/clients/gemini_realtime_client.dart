import 'package:ai_chan/core/interfaces/i_realtime_client.dart';

/// Minimal Gemini realtime client skeleton implementing IRealtimeClient.
/// This is a no-network, pluggable stub used for testing and as a template
/// for a real Gemini transport/adapter implementation.
class GeminiRealtimeClient implements IRealtimeClient {
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({
    required String systemPrompt,
    String voice = 'default',
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    // Simulate connect logic (replace with real transport wiring later)
    _connected = true;
  }

  @override
  void updateVoice(String voice) {
    // No-op for skeleton
  }

  @override
  void appendAudio(List<int> bytes) {
    // No-op for skeleton
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {
    // No-op for skeleton
  }

  @override
  Future<void> commitPendingAudio() async {
    // No-op
  }

  @override
  void sendText(String text) {
    // No-op
  }

  @override
  Future<void> close() async {
    _connected = false;
  }
}
