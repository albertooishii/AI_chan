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
    required final String systemPrompt,
    final String voice = 'default',
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  }) async {
    // Simulate connect logic (replace with real transport wiring later)
    _connected = true;
  }

  @override
  void updateVoice(final String voice) {
    // No-op for skeleton
  }

  @override
  void appendAudio(final List<int> bytes) {
    // No-op for skeleton
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {
    // No-op for skeleton
  }

  @override
  Future<void> commitPendingAudio() async {
    // No-op
  }

  @override
  void sendText(final String text) {
    // No-op
  }

  @override
  Future<void> close() async {
    _connected = false;
  }

  // Implementaciones por defecto de los nuevos métodos (no soportados en Gemini)
  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // No-op - funcionalidad específica de OpenAI gpt-realtime
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    // No-op - funcionalidad específica de OpenAI gpt-realtime
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // No-op - funcionalidad específica de OpenAI gpt-realtime
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // No-op - funcionalidad específica de OpenAI gpt-realtime
  }
}
